import { yupResolver } from '@hookform/resolvers/yup';
import { source } from '@prisma/client';
import { GetServerSideProps } from 'next';
import { useRouter } from 'next/router';
import React from 'react';
import { Col, Row } from 'react-bootstrap';
import { useForm } from 'react-hook-form';
import * as yup from 'yup';
import Auth from '../../components/auth';
import ControlledTypeahead from '../../components/controlledtypeahead';
import { SpeciesUpsertFields } from '../../libs/apitypes';
import { allSources } from '../../libs/db/source';

const Schema = yup.object().shape({
    title: yup.string().required(),
    author: yup.string().required(),
    pubyear: yup.string().matches(/([12][0-9]{3})/),
    citation: yup.string().required(),
});

type Props = {
    sources: source[];
};

const Host = ({ sources }: Props): JSX.Element => {
    const { register, handleSubmit, errors, control, setValue } = useForm({
        mode: 'onBlur',
        resolver: yupResolver(Schema),
    });

    const router = useRouter();

    const onSubmit = async (data: SpeciesUpsertFields) => {
        try {
            const res = await fetch('../api/source/upsert', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data),
            });

            if (res.status === 200) {
                router.push(res.url);
            } else {
                throw new Error(await res.text());
            }
        } catch (e) {
            console.log(e);
        }
    };

    return (
        <Auth>
            <form onSubmit={handleSubmit(onSubmit)} className="m-4 pr-4">
                <h4>Add A Source</h4>
                <Row className="form-group">
                    <Col>
                        Title:
                        <ControlledTypeahead
                            control={control}
                            name="title"
                            onChange={(e) => {
                                const f = sources.find((f) => f.title === e[0]);
                                if (f) {
                                    setValue('author', f.author);
                                    setValue('pubyear', f.pubyear);
                                    setValue('link', f.link);
                                    setValue('citation', f.citation);
                                }
                            }}
                            placeholder="Title"
                            options={sources.map((f) => f.title)}
                            clearButton
                            isInvalid={!!errors.title}
                            newSelectionPrefix="Add a new Source: "
                            allowNew={true}
                        />
                        {errors.title && <span className="text-danger">The Title is required.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Author:
                        <input type="text" placeholder="Author(s)" name="author" className="form-control" ref={register} />
                        {errors.author && <span className="text-danger">You must provide an author.</span>}
                    </Col>
                    <Col>
                        Publication Year:
                        <input type="text" placeholder="Pub Year" name="pubyear" className="form-control" ref={register} />
                        {errors.pubyear && <span className="text-danger">You must provide a valid 4 digit year.</span>}
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        Reference Link:
                        <input type="text" placeholder="Link" name="link" className="form-control" ref={register} />
                    </Col>
                </Row>
                <Row className="form-group">
                    <Col>
                        <p>
                            Citation (
                            <a href="https://www.mybib.com/tools/mla-citation-generator" target="_blank" rel="noreferrer">
                                MLA Form
                            </a>
                            ):
                        </p>
                        <input type="text" placeholder="Citation" name="citation" className="form-control" ref={register} />
                        {errors.citation && <span className="text-danger">You must provide a citation in MLA form.</span>}
                    </Col>
                </Row>
                <input type="submit" className="button" />
            </form>
        </Auth>
    );
};

export const getServerSideProps: GetServerSideProps = async () => {
    return {
        props: {
            sources: await allSources(),
        },
    };
};

export default Host;
