import { ErrorMessage } from '@hookform/error-message';
import { yupResolver } from '@hookform/resolvers/yup';
import { HostDistinctFieldEnum } from '@prisma/client';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import React, { useState } from 'react';
import { Col, ListGroup, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import ControlledTypeahead from '../components/controlledtypeahead';
import { SearchInitialProps } from '../layouts/searchfacets';
import db from '../libs/db/db';
import { alignments, cells, colors, locations, shapes, textures, walls } from '../libs/db/gall';
import { searchGalls } from '../libs/search';
import { Gall, GallLocation, GallTexture, SearchQuery } from '../libs/types';

const dontCare = (o: string | string[] | undefined) => {
    const truthy = !!o;
    return !truthy || (truthy && Array.isArray(o) ? o?.length == 0 : false);
};

const checkLocations = (gallprops: GallLocation[] | null, queryvals: string[] | undefined): boolean => {
    if (gallprops == null || queryvals == undefined) return false;

    return gallprops.some((gp) => gp?.location?.location && queryvals.includes(gp?.location?.location));
};

const checkTextures = (gallprops: GallTexture[] | null, queryvals: string[] | undefined): boolean => {
    if (gallprops == null || queryvals == undefined) return false;

    return gallprops.some((gp) => gp?.texture?.texture && queryvals.includes(gp?.texture?.texture));
};

const checkGall = (g: Gall, q: SearchQuery): boolean => {
    const alignment = dontCare(q.alignment) || (!!g.alignment && g.alignment?.alignment === q.alignment);
    const cells = dontCare(q.cells) || (!!g.cells && g.cells?.cells === q.cells);
    const color = dontCare(q.color) || (!!g.color && g.color?.color === q.color);
    const detachable = dontCare(q.detachable) || (!!g.detachable && (g.detachable == 0 ? 'no' : 'yes') === q.detachable);
    const shape = dontCare(q.shape) || (!!g.shape && g.shape?.shape === q.shape);
    const walls = dontCare(q.walls) || (!!g.walls && g.walls?.walls === q.walls);
    const location = dontCare(q.locations) || (!!g.galllocation && checkLocations(g.galllocation, q.locations));
    const texture = dontCare(q.cells) || (!!g.galltexture && checkTextures(g.galltexture, q.textures));

    return alignment && cells && color && detachable && shape && walls && location && texture;
};

const schema = yup.object().shape({
    host: yup.string().required(),
});

type Props = SearchInitialProps & {
    galls: Gall[];
};

const Search2 = (props: Props): JSX.Element => {
    const router = useRouter();

    // init local state with a copy of the galls passed in from props, this way we can filter easily
    const [galls, setGalls] = useState(props.galls);
    const [query, setQuery] = useState(router.query as SearchQuery);

    console.log(`rendering with ${JSON.stringify(query)} and ${galls.length} galls.`);

    const { errors, control } = useForm({
        defaultValues: {
            host: query.host,
            locations: '',
            detachable: '',
            textures: '',
            alignment: '',
            walls: '',
            cells: '',
            shape: '',
            color: '',
        },
        resolver: yupResolver(schema),
    });

    const updateQuery = (f: string, v: string | string[]): SearchQuery => {
        const qq = { ...query } as SearchQuery;
        (qq as Record<string, string | string[]>)[f] = v;
        return qq;
    };

    const doSearch = async (field: string, value: string | string[]) => {
        const newq = updateQuery(field, value);
        if (field == 'host') {
            // for host we need to reload the page to fetch the galls for the new host
            const x = {
                pathname: '/search2',
                query: newq,
            };
            console.log(`HOSTCHANGE: ${JSON.stringify(x, null, '  ')}`);
            router.push(x);
            //            router.reload();
        } else {
            const filtered = props.galls.filter((g) => checkGall(g, newq));
            console.log(
                `filtered galls: ${JSON.stringify(
                    filtered.map((x) => x.species?.name),
                    null,
                    '  ',
                )}`,
            );
            setGalls(filtered);
            setQuery(newq);
        }
    };

    // keep TS happy since the allowable field values are bound when we set the defaultValues above in the useForm() call.
    type FieldNames = 'host' | 'locations' | 'detachable' | 'textures' | 'alignment' | 'walls' | 'cells' | 'shape' | 'color';

    const makeFormInput = (field: FieldNames, opts: string[], rules = {}) => {
        return (
            <ControlledTypeahead
                control={control}
                name={field}
                onChange={(e) => {
                    doSearch(field, e ? (e as string[]) : []);
                }}
                placeholder={field.charAt(0).toUpperCase() + field.slice(1)}
                clearButton={field !== 'host'}
                options={opts}
            />
        );
    };

    return (
        <>
            <Row>
                <Col xs={3}>
                    <form className="fixed-left border p-2 mt-2">
                        Host:
                        {makeFormInput('host', props.hosts)}
                        <ErrorMessage errors={errors} name="host-error" />
                        Location:
                        {makeFormInput('locations', props.locations)}
                        Detachable:
                        {makeFormInput('detachable', ['yes', 'no', 'unsure'])}
                        Texture:
                        {makeFormInput('textures', props.textures)}
                        Aligment:
                        {makeFormInput('alignment', props.alignments)}
                        Walls:
                        {makeFormInput('walls', props.walls)}
                        Cells:
                        {makeFormInput('cells', props.cells)}
                        Shape:
                        {makeFormInput('shape', props.shapes)}
                        Color:
                        {makeFormInput('color', props.colors)}
                    </form>
                </Col>
                <Col className="border mt-2">
                    {/* <Row className='border m-2'><p className='text-right'>Pager TODO</p></Row> */}
                    <Row className="m-2">
                        <ListGroup>
                            {galls.length == 0 ? (
                                query.host == undefined ? (
                                    <p>To begin with select a Host to see matching galls.</p>
                                ) : (
                                    <p>There are no galls that match your filter.</p>
                                )
                            ) : (
                                galls.map((g) => (
                                    <ListGroup.Item key={g.species_id}>
                                        <img src="images/gall.jpg" width="75px" height="75px" />{' '}
                                        <Link href={`gall/${g.species_id}`}>
                                            <a>{g.species?.name}</a>
                                        </Link>
                                        - {gallDescription(g)}
                                    </ListGroup.Item>
                                ))
                            )}
                        </ListGroup>
                    </Row>
                </Col>
            </Row>
        </>
    );
};

const gallDescription = (g: Gall): string => {
    if (g.species && g.species.description) {
        if (g.species.description.length > 400) {
            return g.species.description.slice(0, 400) + '...';
        } else {
            return g.species.description;
        }
    }
    return '';
};

export const getServerSideProps: GetServerSideProps = async (context) => {
    // get the list of galls for the host if there is a host passed in
    const q = context.query as SearchQuery;
    const galls = q.host ? await searchGalls(q) : new Array<Gall>();
    console.log(`Got ${galls.length} galls`);

    // get all of the data for the typeahead boxes
    const h = await db.host.findMany({
        include: {
            hostspecies: {},
        },
        distinct: [HostDistinctFieldEnum.host_species_id],
    });
    const hosts = h
        .flatMap((h) => {
            if (h.hostspecies != null) return [h.hostspecies.name, h.hostspecies.commonnames];
            else return [];
        })
        .filter((h) => h)
        .sort();

    return {
        props: {
            galls: galls,
            hosts: hosts,
            locations: await locations(),
            colors: await colors(),
            shapes: await shapes(),
            textures: await textures(),
            alignments: await alignments(),
            walls: await walls(),
            cells: await cells(),
        },
    };
};

export default Search2;
