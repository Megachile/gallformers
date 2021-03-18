import { abundance } from '@prisma/client';
import { constant, pipe } from 'fp-ts/lib/function';
import * as O from 'fp-ts/lib/Option';
import { GetServerSideProps } from 'next';
import Link from 'next/link';
import { useRouter } from 'next/router';
import { ParsedUrlQuery } from 'querystring';
import React, { useState } from 'react';
import { Button, Col, Row } from 'react-bootstrap';
import 'react-bootstrap-table-next/dist/react-bootstrap-table2.min.css';
import * as yup from 'yup';
import AliasTable from '../../components/aliastable';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { RenameEvent } from '../../components/editname';
import useAdmin from '../../hooks/useadmin';
import { AdminFormFields } from '../../hooks/useAPIs';
import { useConfirmation } from '../../hooks/useconfirmation';
import { extractQueryParam } from '../../libs/api/apipage';
import {
    AbundanceApi,
    AliasApi,
    EmptyAbundance,
    HostApi,
    HostTaxon,
    HOST_FAMILY_TYPES,
    SpeciesUpsertFields,
} from '../../libs/api/apitypes';
import { EMPTY_FGS, FGS, GENUS, TaxonomyEntry } from '../../libs/api/taxonomy';
import { allHosts } from '../../libs/db/host';
import { abundances } from '../../libs/db/species';
import { allFamilies, allGenera, allSections, taxonomyForSpecies } from '../../libs/db/taxonomy';
import Admin from '../../libs/pages/admin';
import { mightFail, mightFailWithArray } from '../../libs/utils/util';

type Props = {
    id: string;
    hs: HostApi[];
    fgs: FGS;
    families: TaxonomyEntry[];
    sections: TaxonomyEntry[];
    genera: TaxonomyEntry[];
    abundances: abundance[];
};

const extractGenus = (n: string): string => {
    return n.split(' ')[0];
};

const schema = yup.object().shape({
    value: yup
        .array()
        .of(
            yup.object({
                name: yup
                    .string()
                    // maybe? add this back but allow select punctuation in species name?
                    // .matches(/([A-Z][a-z]+ [a-z]+$)/)
                    .required(),
            }),
        )
        .min(1)
        .max(1),
    family: yup.mixed().required(),
});

export type FormFields = AdminFormFields<HostApi> & {
    genus: TaxonomyEntry[];
    family: TaxonomyEntry[];
    section: TaxonomyEntry[];
    abundance: AbundanceApi[];
    datacomplete: boolean;
};

export const testables = {
    extractGenus: extractGenus,
    Schema: schema,
};

const updateHost = (s: HostApi, newValue: string): HostApi => ({
    ...s,
    name: newValue,
});

const emptyForm = {
    value: [],
    genus: [],
    family: [],
    abundance: [EmptyAbundance],
};

const fetchFGS = async (h: HostApi): Promise<FGS> => {
    const res = await fetch(`../api/taxonomy?id=${h.id}`);
    if (res.status === 200) {
        return await res.json();
    } else {
        console.error(await res.text());
        throw new Error('Failed to fetch taxonomy for the selected species. Check console.');
    }
};

const Host = ({ id, hs, fgs, genera, families, sections, abundances }: Props): JSX.Element => {
    const [theFGS, setTheFGS] = useState(fgs);
    const [aliasData, setAliasData] = useState<AliasApi[]>([]);

    const convertToFields = (s: HostApi): FormFields => ({
        value: [s],
        genus: [theFGS.genus],
        family: [theFGS.family],
        section: pipe(
            theFGS.section,
            O.fold(constant([]), (s) => [s]),
        ),
        abundance: [pipe(s.abundance, O.getOrElse(constant(EmptyAbundance)))],
        datacomplete: s.datacomplete,
        del: false,
    });

    const toUpsertFields = (fields: FormFields, name: string, id: number): SpeciesUpsertFields => {
        return {
            abundance: fields.abundance[0].abundance,
            aliases: aliasData,
            datacomplete: fields.datacomplete,
            fgs: theFGS.family.id == fields.family[0].id ? theFGS : { ...theFGS, family: fields.family[0] },
            id: id,
            name: name,
        };
    };

    const onDataChangeCallback = async (s: HostApi | undefined): Promise<HostApi | undefined> => {
        if (s == undefined) {
            setAliasData([]);
        } else {
            const newFGS = await fetchFGS(s);
            setTheFGS(newFGS);
            setAliasData(s.aliases);
        }
        return s;
    };

    const {
        data,
        selected,
        setSelected,
        showRenameModal,
        setShowRenameModal,
        error,
        setError,
        deleteResults,
        setDeleteResults,
        renameCallback,
        form,
        formSubmit,
    } = useAdmin(
        'Host',
        id,
        hs,
        updateHost,
        convertToFields,
        toUpsertFields,
        { keyProp: 'name', delEndpoint: '../api/host/', upsertEndpoint: '../api/host/upsert' },
        schema,
        emptyForm,
        onDataChangeCallback,
    );

    const router = useRouter();
    const confirm = useConfirmation();

    const rename = async (fields: FormFields, e: RenameEvent) => {
        if (e.old == undefined) throw new Error('Trying to add rename but old name is missing?!');

        if (e.addAlias) {
            aliasData.push({
                id: -1,
                name: e.old,
                type: 'scientific',
                description: 'Previous name',
            });
        }

        // have to check for genus rename
        const newGenus = extractGenus(e.new);
        if (newGenus.localeCompare(extractGenus(e.old)) != 0) {
            const g = genera.find((g) => g.name.localeCompare(newGenus) == 0);
            if (g == undefined) {
                return confirm({
                    variant: 'danger',
                    catchOnCancel: true,
                    title: 'Are you sure want to create a new genus?',
                    message: `Renaming the genus to ${newGenus} will create a new genus under the current family ${fields.family[0].name}. Do you want to continue?`,
                }).then(() => {
                    fields.genus[0] = {
                        id: -1,
                        description: '',
                        name: newGenus,
                        type: GENUS,
                        parent: O.of(fields.family[0]),
                    };
                    return Promise.bind(onSubmit(fields));
                });
            } else {
                fields.genus[0] = g;
            }
        }

        return onSubmit(fields);
    };

    const onSubmit = async (fields: FormFields) => {
        formSubmit(fields);
    };

    return (
        <Admin
            type="Host"
            keyField="name"
            editName={{ getDefault: () => selected?.name, renameCallback: renameCallback(rename) }}
            setShowModal={setShowRenameModal}
            showModal={showRenameModal}
            setError={setError}
            error={error}
            setDeleteResults={setDeleteResults}
            deleteResults={deleteResults}
        >
            <form onSubmit={form.handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add/Edit Hosts</h4>
                <p>
                    This is for all of the details about a Host. To add a description (which must be referenced to a source) go
                    add <Link href="/admin/source">Sources</Link>, if they do not already exist, then go{' '}
                    <Link href="/admin/speciessource">map species to sources with description</Link>. If you want to assign a{' '}
                    <Link href="/admin/family">Family</Link> or <Link href="/admin/section">Section</Link> then you will need to
                    have created them first if they do not exist.
                </p>
                <Row className="form-group">
                    <Col>
                        <Row>
                            <Col xs={8}>Name (binomial):</Col>
                        </Row>
                        <Row>
                            <Col>
                                <ControlledTypeahead
                                    control={form.control}
                                    name="value"
                                    onChangeWithNew={(e, isNew) => {
                                        if (isNew || !e[0]) {
                                            setSelected(undefined);
                                            router.replace(``, undefined, { shallow: true });
                                        } else {
                                            const host: HostApi = e[0];
                                            console.log(`selected: ${selected?.id} // host: ${host.id}`);
                                            if (selected?.id !== host.id) {
                                                setSelected(host);
                                                router.replace(`?id=${host.id}`, undefined, { shallow: true });
                                            }
                                        }
                                    }}
                                    onBlurT={(e) => {
                                        if (!form.errors.value) {
                                            const h = genera.find((h) => h.name.localeCompare(extractGenus(e.target.value)));
                                            form.setValue('genus', h ? [h] : []);
                                        }
                                    }}
                                    placeholder="Name"
                                    options={data}
                                    labelKey="name"
                                    clearButton
                                    isInvalid={!!form.errors.value}
                                    newSelectionPrefix="Add a new Host: "
                                    allowNew={true}
                                />
                                {form.errors.value && (
                                    <span className="text-danger">
                                        Name is required and must be in standard binomial form, e.g., Gallus gallus
                                    </span>
                                )}
                            </Col>
                            {selected && (
                                <Col xs={1}>
                                    <Button variant="secondary" className="btn-sm" onClick={() => setShowRenameModal(true)}>
                                        Rename
                                    </Button>
                                </Col>
                            )}
                        </Row>
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Genus (filled automatically):
                        <ControlledTypeahead
                            control={form.control}
                            name="genus"
                            options={genera}
                            labelKey="name"
                            disabled={true}
                        />
                    </Col>
                    <Col>
                        Family:
                        <ControlledTypeahead
                            control={form.control}
                            name="family"
                            placeholder="Family"
                            options={families}
                            labelKey="name"
                            clearButton
                            disabled={!!selected}
                        />
                        {form.errors.family && (
                            <span className="text-danger">
                                The Family name is required. If it is not present in the list you will have to go add the family
                                first. :(
                            </span>
                        )}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Section:
                        <ControlledTypeahead
                            control={form.control}
                            name="section"
                            placeholder="Section"
                            options={sections}
                            labelKey="name"
                            clearButton
                        />
                    </Col>
                    <Col>
                        Abundance:
                        <ControlledTypeahead
                            control={form.control}
                            name="abundance"
                            placeholder=""
                            options={abundances}
                            labelKey="abundance"
                            clearButton
                        />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <AliasTable data={aliasData} setData={setAliasData} />
                    </Col>
                </Row>
                <Row className="formGroup pb-1">
                    <Col className="mr-auto">
                        <input name="datacomplete" type="checkbox" className="form-input-checkbox" ref={form.register} /> Are all
                        known galls submitted for this host?
                    </Col>
                </Row>
                <Row className="fromGroup pb-1" hidden={!selected}>
                    <Col className="mr-auto">
                        <input name="del" type="checkbox" className="form-input-checkbox" ref={form.register} /> Delete?
                    </Col>
                </Row>
                <Row className="formGroup">
                    <Col>
                        <input type="submit" className="button" value="Submit" />
                    </Col>
                </Row>
                <Row hidden={!selected}>
                    <Col>
                        <br />
                        <Link href={`./images?speciesid=${selected?.id}`}>Add/Edit Images for this Host</Link>
                    </Col>
                </Row>
            </form>
        </Admin>
    );
};

export const getServerSideProps: GetServerSideProps = async (context: { query: ParsedUrlQuery }) => {
    const queryParam = 'id';
    // eslint-disable-next-line prettier/prettier
    const id = pipe(
        extractQueryParam(context.query, queryParam),
        O.getOrElse(constant('')),
    );

    const fgs = id === '' ? EMPTY_FGS : await mightFail(constant(EMPTY_FGS))(taxonomyForSpecies(parseInt(id)));
    return {
        props: {
            id: id,
            hs: await mightFailWithArray<HostApi>()(allHosts()),
            fgs: fgs,
            families: await mightFailWithArray<TaxonomyEntry>()(allFamilies(HOST_FAMILY_TYPES)),
            genera: await mightFailWithArray<TaxonomyEntry>()(allGenera(HostTaxon)),
            sections: await mightFailWithArray<TaxonomyEntry>()(allSections()),
            abundances: await mightFailWithArray<AbundanceApi>()(abundances()),
        },
    };
};

export default Host;
