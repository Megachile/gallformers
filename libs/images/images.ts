import { PutObjectCommand, S3Client, S3ClientConfig } from '@aws-sdk/client-s3';
import { S3RequestPresigner } from '@aws-sdk/s3-request-presigner';
import { createRequest } from '@aws-sdk/util-create-request';
import { formatUrl } from '@aws-sdk/util-format-url';
import { image } from '@prisma/client';
import Jimp from 'jimp';
import { ImagePaths } from '../api/apitypes';
import db from '../db/db';
import { logger } from '../utils/logger';
import { tryBackoff } from '../utils/network';

const ENDPOINT = 'https://nyc3.digitaloceanspaces.com';
const config: S3ClientConfig = {
    // logger: console,
    region: 'nyc3',
    endpoint: ENDPOINT,
    credentials: {
        accessKeyId: process.env.AWS_ACCESS_KEY_ID == undefined ? '' : process.env.AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY == undefined ? '' : process.env.AWS_SECRET_ACCESS_KEY,
    },
};

const EDGE = 'https://static.gallformers.org/';
const BUCKET = 'gallformers';
const client = new S3Client(config);

// add a middleware to work around bug. See: https://github.com/aws/aws-sdk-js-v3/issues/1800
client.middlewareStack.add(
    (next) => async (args) => {
        // eslint-disable-next-line @typescript-eslint/ban-ts-comment
        // @ts-ignore
        delete args.request.headers['content-type'];
        return next(args);
    },
    { step: 'build' },
);

const ORIGINAL = 'original';
const SMALL = 'small';
const MEDIUM = 'medium';
const LARGE = 'large';
type ImageSize = typeof ORIGINAL | typeof SMALL | typeof MEDIUM | typeof LARGE;

export const getImagePaths = async (speciesId: number): Promise<ImagePaths> => {
    try {
        const images = await db.image.findMany({
            where: { speciesimage: { every: { species_id: speciesId } } },
            orderBy: { id: 'asc' },
        });

        return toImagePaths(images);
    } catch (e) {
        logger.error(e);
    }

    return {
        small: [],
        medium: [],
        large: [],
        original: [],
    };
};

export const toImagePaths = (images: image[]): ImagePaths => {
    const makePath = (path: string, size: ImageSize): string => `${EDGE}/${path.replace(ORIGINAL, size)}`;

    return images.reduce(
        (paths, image) => {
            paths.small.push(makePath(image.path, SMALL));
            paths.medium.push(makePath(image.path, MEDIUM));
            paths.large.push(makePath(image.path, LARGE));
            paths.original.push(makePath(image.path, ORIGINAL));

            return paths;
        },
        {
            small: new Array<string>(),
            medium: new Array<string>(),
            large: new Array<string>(),
            original: new Array<string>(),
        } as ImagePaths,
    );
};

const EXPIRE_SECONDS = 60 * 5;

export const getPresignedUrl = async (path: string): Promise<string> => {
    console.log(`${new Date().toString()}: Spaces API Call PRESIGNED URL GET for ${path}.`);

    const signer = new S3RequestPresigner({ ...client.config });
    const request = await createRequest(client, new PutObjectCommand({ Key: path, Bucket: BUCKET }));

    return formatUrl(await signer.presign(request, { expiresIn: EXPIRE_SECONDS }));
};

const sizes = new Map([
    [SMALL, 300],
    [MEDIUM, 800],
    [LARGE, 1200],
]);

export const createOtherSizes = (images: image[]): image[] => {
    try {
        images.map(async (image) => {
            const path = `${ENDPOINT}/${BUCKET}/${image.path}`;
            console.log(`trying to load: ${path}`);
            const img = await tryBackoff(3, () => Jimp.read(path)).catch((reason: Error) =>
                logger.error(`Failed to load file ${path} with Jimp. Received error: ${reason}.`),
            );
            if (!img) return [];

            const mime = img.getMIME();
            console.log(`Read file with mime type: ${mime}.`);
            sizes.forEach(async (value, key) => {
                img.resize(value, Jimp.AUTO);
                img.quality(90);
                const newPath = image.path.replace(ORIGINAL, key);
                console.log(`Will write ${newPath}`);
                const buffer = await img.getBufferAsync(mime);
                await uploadImage(newPath, buffer, mime);
            });
        });

        return images;
    } catch (e) {
        logger.error('Err in createOtherSizes: ' + e);
        return [];
    }
};

const uploadImage = async (key: string, buffer: Buffer, mime: string) => {
    const uploadParams = {
        Bucket: BUCKET,
        Key: key,
        Body: buffer,
        ContentType: mime,
        ACL: 'public-read',
    };

    try {
        console.log(`Uploading new image ${key}`);
        await tryBackoff(
            3,
            () => client.send(new PutObjectCommand(uploadParams)),
            (t) => t.$metadata.httpStatusCode !== 503,
        );
    } catch (e) {
        console.log('Err in uploadImage: ' + JSON.stringify(e));
    }
};