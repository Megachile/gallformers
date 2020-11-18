import { yupResolver } from '@hookform/resolvers/yup';
import { abundance, alignment, cells as cs, color, family, location, shape, species, texture, walls as ws } from '@prisma/client';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { GallRes, GallUpsertFields } from '../../libs/apitypes';
import { allFamilies } from '../../libs/db/family';
import { alignments, allGalls, cells, colors, locations, shapes, textures, walls } from '../../libs/db/gall';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { mightBeNull } from '../../libs/db/utils';
import { GallFormFields, genOptions } from '../../libs/utils/forms';

//TODO factor out the species form and allow it to be extended with what is needed for a gall as this code violates DRY a lot!
type Host = {
    id: number;
    name: string;
    commonnames: string;
};

type Props = {
    galls: species[];
    abundances: abundance[];
    hosts: Host[];
    locations: location[];
    colors: color[];
    shapes: shape[];
    textures: texture[];
    alignments: alignment[];
    walls: ws[];
    cells: cs[];
    families: family[];
};

const Schema = yup.object().shape({
    name: yup.string().matches(/([A-Z][a-z]+ [a-z]+$)/),
    family: yup.string().required(),
    description: yup.string().required(),
    hosts: yup.array().required(),
});

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

type FormFields =
    | 'name'
    | 'genus'
    | 'family'
    | 'abundance'
    | 'commonnames'
    | 'synonmys'
    | 'hosts'
    | 'detachable'
    | 'walls'
    | 'cells'
    | 'alignment'
    | 'shape'
    | 'color'
    | 'locations'
    | 'textures'
    | 'description';

const Gall = ({
    galls,
    hosts,
    locations,
    colors,
    shapes,
    textures,
    alignments,
    walls,
    cells,
    abundances,
    families,
}: Props): JSX.Element => {
    const { register, handleSubmit, errors, control, setValue } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });
    const router = useRouter();

    const setValueForLookup = (
        field: FormFields,
        ids: (number | null | undefined)[] | undefined,
        lookup: any[],
        valField: string,
    ) => {
        if (!ids) return;

        const vals = ids.map((id) => {
            const val = lookup.find((v) => v.id === id);
            if (val) {
                return val[valField];
            } else if (!id) {
                // was an invalid id so do not care
                return undefined;
            } else {
                throw new Error(`Failed to lookup for ${field}.`);
            }
        });
        if (vals && vals.length > 0 && vals[0]) {
            setValue(field, vals);
        }
    };

    const setGallDetails = async (spid: number): Promise<void> => {
        try {
            const res = await fetch(`../api/gall?speciesid=${spid}`);
            const gall = (await res.json()) as GallRes;

            setValue('detachable', gall.detachable);
            setValueForLookup('walls', [gall.walls_id], walls, 'walls');
            setValueForLookup('cells', [gall.cells_id], cells, 'cells');
            setValueForLookup('alignment', [gall.alignment_id], alignments, 'alignment');
            setValueForLookup('color', [gall.color_id], colors, 'color');
            setValueForLookup('shape', [gall.shape_id], shapes, 'shape');
            setValueForLookup('locations', gall.locations, locations, 'location');
            setValueForLookup('textures', gall.textures, textures, 'texture');
            setValueForLookup('hosts', gall.hosts, hosts, 'name');
        } catch (e) {
            console.error(e);
        }
    };

    const onSubmit = async (data: GallFormFields) => {
        const species = galls.find((g) => g.name === data.name);

        const submitData: GallUpsertFields = {
            ...data,
            // i hate null... :( these should be safe since the text values came from the same place as the ids
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            hosts: data.hosts.map((h) => hosts.find((hh) => hh.name === h)!.id),
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            locations: data.locations.map((l) => locations.find((ll) => ll.location === l)!.id),
            // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
            textures: data.textures.map((t) => textures.find((tt) => tt.texture === t)!.id),
            id: species ? species.id : undefined,
        };
        try {
            const res = await fetch('../api/gall/upsert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(submitData),
            });

            if (res.status === 200) {
                router.push(res.url);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.error(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Gall</h4>
                <Row className="form-group">
                    <Col>
                        Name (binomial):
                        <ControlledTypeahead
                            control={control}
                            name="name"
                            onChange={(e) => {
                                const f = galls.find((f) => f.name === e[0]);
                                if (f) {
                                    setValueForLookup('family', [f.family_id], families, 'name');
                                    setValueForLookup('abundance', [f.abundance_id as number | undefined], abundances, 'name');
                                    setValue('commonnames', f.commonnames);
                                    setValue('synonyms', f.synonyms);
                                    setGallDetails(f.id);
                                    setValue('description', f.description);
                                }
                            }}
                            onBlur={(e) => {
                                if (!errors.name) {
                                    setValue('genus', extractGenus(e.target.value));
                                }
                            }}
                            placeholder="Name"
                            options={galls.map((f) => f.name)}
                            clearButton
                            isInvalid={!!errors.name}
                            newSelectionPrefix="Add a new Gall: "
                            allowNew={true}
                        />
                        {errors.name && (
                            <span className="text-danger">
                                Name is required and must be in standard binomial form, e.g., Andricus weldi
                            </span>
                        )}
                    </Col>
                    <Col>
                        Genus (filled automatically):
                        <input type="text" name="genus" className="form-control" readOnly tabIndex={-1} ref={register} />
                    </Col>
                    <Col>
                        Family:
                        <select name="family" className="form-control" ref={register}>
                            {genOptions(families.map((f) => mightBeNull(f.name)))}
                        </select>
                        {errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                    <Col>
                        Abundance:
                        <select name="abundance" className="form-control" ref={register}>
                            {genOptions(abundances.map((a) => mightBeNull(a.abundance)))}
                        </select>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Common Names (comma-delimited):
                        <input
                            type="text"
                            placeholder="Common Names"
                            name="commonnames"
                            className="form-control"
                            ref={register}
                        />
                    </Col>
                    <Col>
                        Synonyms (comma-delimited):
                        <input type="text" placeholder="Synonyms" name="synonyms" className="form-control" ref={register} />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Hosts:
                        <ControlledTypeahead
                            control={control}
                            name="hosts"
                            placeholder="Hosts"
                            options={hosts.map((h) => h.name)}
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Detachable:
                        <input
                            type="checkbox"
                            placeholder="Detachable"
                            name="detachable"
                            className="form-control"
                            ref={register}
                        />
                    </Col>
                    <Col>
                        Walls:
                        <select name="walls" className="form-control" ref={register}>
                            {genOptions(walls.map((w) => mightBeNull(w.walls)))}
                        </select>
                    </Col>
                    <Col>
                        Cells:
                        <select name="cells" className="form-control" ref={register}>
                            {genOptions(cells.map((c) => mightBeNull(c.cells)))}
                        </select>
                    </Col>
                    <Col>
                        Alignment:
                        <select name="alignment" className="form-control" ref={register}>
                            {genOptions(alignments.map((a) => mightBeNull(a.alignment)))}
                        </select>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Color:
                        <select name="color" className="form-control" ref={register}>
                            {genOptions(colors.map((c) => mightBeNull(c.color)))}
                        </select>
                    </Col>
                    <Col>
                        Shape:
                        <select name="shape" className="form-control" ref={register}>
                            {genOptions(shapes.map((s) => mightBeNull(s.shape)))}
                        </select>
                    </Col>{' '}
                </Row>
                <Row className="form-group">
                    <Col>
                        Location(s):
                        <ControlledTypeahead
                            control={control}
                            name="locations"
                            placeholder="Location(s)"
                            options={locations.map((l) => l.location)}
                            multiple
                            clearButton
                        />
                    </Col>
                    <Col>
                        Texture(s):
                        <ControlledTypeahead
                            control={control}
                            name="textures"
                            placeholder="Texture(s)"
                            options={textures.map((t) => t.texture)}
                            multiple
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Description:
                        <textarea name="description" className="form-control" ref={register} rows={8} />
                        {errors.description && (
                            <span className="text-danger">
                                You must provide a description. You can add source references separately.
                            </span>
                        )}
                    </Col>
                </Row>
                <input type="submit" className="button" />
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    const h = await allHosts();
    const hosts: Host[] = h
        .map((h) => {
            return {
                name: h.name,
                id: h.id,
                commonnames: mightBeNull(h.commonnames),
            };
        })
        .sort((a, b) => a.name?.localeCompare(b.name));

    return {
        props: {
            galls: await allGalls(),
            hosts: hosts,
            families: await allFamilies(),
            locations: await locations(),
            colors: await colors(),
            shapes: await shapes(),
            textures: await textures(),
            alignments: await alignments(),
            walls: await walls(),
            cells: await cells(),
            abundances: await abundances(),
        },
    };
};

export default Gall;
