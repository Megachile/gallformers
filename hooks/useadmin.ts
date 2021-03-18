import { yupResolver } from '@hookform/resolvers/yup';
import router from 'next/router';
import { useCallback, useEffect, useState } from 'react';
import { DeepPartial, UnpackNestedValue, useForm, UseFormMethods } from 'react-hook-form';
import toast from 'react-hot-toast';
import * as yup from 'yup';
import { RenameEvent } from '../components/editname';
import { DeleteResult } from '../libs/api/apitypes';
import { WithID } from '../libs/utils/types';
import { AdminFormFields, useAPIs } from './useAPIs';

type AdminData<T, FormFields> = {
    data: T[];
    selected?: T;
    setSelected: (t: T | undefined) => void;
    showRenameModal: boolean;
    setShowRenameModal: (show: boolean) => void;
    error: string;
    setError: (err: string) => void;
    deleteResults?: DeleteResult;
    setDeleteResults: (dr: DeleteResult) => void;
    renameCallback: (doRename: (s: FormFields, e: RenameEvent) => void) => (e: RenameEvent) => void;
    form: UseFormMethods<FormFields>;
    formSubmit: (fields: FormFields) => Promise<void>;
};

/**
 *  * A hook to handle universal adminstration data and logic. Works in conjunction with @Admin

 * @param type a string representing the type of data being Adminstered.
 * @param id the initial id that is selected, could be undefined
 * @param ts an array of the data type
 * @param update a function to create a new T from a give T and a new value for its "key"
 * @param toFormFields a function that converts a T to FormFields
 * @param toUpsertFields a function that converts FormFields to UpsertFields
 * @param apiConfig the configuration for the API endpoints
 * @param schema the form validation schema
 * @param emptyForm an empty FormFields to use when resetting the form to empty
 * @param onDataChangeCallback a callback that is called with the data selection changes
 * @returns 
 */
const useAdmin = <T extends WithID, FormFields extends AdminFormFields<T>, UpsertFields>(
    type: string,
    id: string | undefined,
    ts: T[],
    update: (t: T, tName: string) => T,
    toFormFields: (t: T) => FormFields,
    toUpsertFields: (fields: FormFields, keyField: string, id: number) => UpsertFields,
    apiConfig: { keyProp: keyof T; delEndpoint: string; upsertEndpoint: string },
    schema: yup.ObjectSchema,
    emptyForm: UnpackNestedValue<DeepPartial<FormFields>>,
    onDataChangeCallback: (t: T | undefined) => Promise<T | undefined> = (t: T | undefined) => Promise.resolve(t),
): AdminData<T, FormFields> => {
    const [data, setData] = useState(ts);
    const [selected, setSelected] = useState<T | undefined>(id ? data.find((d) => d.id === parseInt(id)) : undefined);
    const [showModal, setShowModal] = useState(false);
    const [error, setError] = useState('');
    const [deleteResults, setDeleteResults] = useState<DeleteResult>();

    const { doDeleteOrUpsert } = useAPIs<T, UpsertFields>(apiConfig.keyProp, apiConfig.delEndpoint, apiConfig.upsertEndpoint);

    const form = useForm<FormFields>({
        mode: 'onBlur',
        resolver: yupResolver(schema),
    });

    const postDelete = (id: number | string, result: DeleteResult) => {
        setData(data.filter((d) => d.id !== id));
        setDeleteResults(result);
        setSelected(undefined);
        toast.success(`${type} deleted`);
        router.replace(``, undefined, { shallow: true });
    };

    const postUpdate = async (res: Response) => {
        const s = (await res.json()) as T;
        setSelected(s);
        const updated = data;
        if (data.find((d) => d.id === s.id) == undefined) {
            // add new if necessary
            updated.push(s);
        } else {
            // update data in place since name might have changed
            const updated = data.filter((d) => d.id == s.id);
            updated.push(s);
        }
        setData(updated);
        toast.success(`${type} Updated`);
        router.replace(`?id=${s.id}`, undefined, { shallow: true });
    };

    const formSubmit = async (fields: FormFields) => {
        await doDeleteOrUpsert(fields, postDelete, postUpdate, toUpsertFields)
            .then(() => form.reset())
            .catch((e: unknown) => setError(`Failed to save changes. ${e}.`));
    };

    const renameCallback = (doRename: (s: FormFields, e: RenameEvent) => void) => (e: RenameEvent) => {
        if (selected == undefined) {
            const msg = `You encountered a bug. The current selection is invalid in the middle of a rename operation.`;
            console.error(msg);
            setError(msg);
            return;
        }
        const updated = update(selected, e.new);
        doRename(toFormFields(updated), e);
        setData(data.map((d) => (d.id === updated.id ? updated : d)));
        setSelected(updated);
    };

    const onDataChange = useCallback(async (t: T | undefined) => {
        const newT = await onDataChangeCallback(t);
        if (newT == undefined) {
            form.reset(emptyForm);
        } else {
            try {
                // TODO eliminate cast. how?
                form.reset(toFormFields(newT) as UnpackNestedValue<DeepPartial<FormFields>>);
            } catch (e) {
                console.error(e);
                setError(e);
            }
        }
        // we are using form.reset, emptyForm, and onDataChangeCallback. these may get re-bound by React but they are
        // not going to change in any meaningful way. If we add them we will just get infinite render loops.
        // The real triggers for re-rendering that we care about are in the useEffect deps array below.
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    useEffect(() => {
        onDataChange(selected);
    }, [selected, onDataChange]);

    return {
        data: data,
        selected: selected,
        setSelected: setSelected,
        showRenameModal: showModal,
        setShowRenameModal: setShowModal,
        error: error,
        setError: setError,
        deleteResults: deleteResults,
        setDeleteResults: setDeleteResults,
        renameCallback: renameCallback,
        form: form,
        formSubmit: formSubmit,
    };
};

export default useAdmin;
