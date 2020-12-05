import { pipe } from 'fp-ts/lib/function';
import * as TE from 'fp-ts/lib/TaskEither';
import { TaskEither } from 'fp-ts/lib/TaskEither';
import { PorterStemmer, WordTokenizer } from 'natural';
import React, { ReactNode } from 'react';
import { allGlossaryEntries, Entry } from './db/glossary';
import { serialize } from './reactserialize';

export type EntryLinked = {
    word: string;
    linkedDefinition: string | JSX.Element[];
    definition: string;
    urls: string[];
};

interface WordStem {
    word: string;
    stem: string;
}

const makelink = (linkname: string, display: string, samepage: boolean): JSX.Element => {
    const href = samepage ? `#${linkname}` : `/glossary/#${linkname}`;
    return React.createElement('a', { href: href }, display);
};

/**
 * Given the input text, add links to any word that occurs in the global glossary.
 *
 * @param text the text to find and link glossary terms in.
 * @param samepage a flag to signify if the links are on the same page.
 */
export function linkTextFromGlossary(text: string | null | undefined, samepage = false): TaskEither<Error, ReactNode[]> {
    const toWordStem = (e: Entry): WordStem => {
        return <WordStem>{
            ...e,
            stem: PorterStemmer.stem(e.word),
        };
    };

    const linkFromStems = (stems: WordStem[]): ReactNode[] => {
        const els: ReactNode[] = [];
        if (text != undefined && text !== null && (text as string).length > 0) {
            let curr = 0;
            const tokens = new WordTokenizer().tokenize(text);
            tokens.forEach((t, i) => {
                const stemmed = PorterStemmer.stem(t);
                const raw = tokens[i];
                //  console.log(`t: '${t}' -- i: '${i}' -- stemmed: '${stemmed}' -- raw: '${raw}'`);
                stems.forEach((stem) => {
                    if (stem.stem === stemmed) {
                        const left = text.substring(curr, text.indexOf(raw, curr));
                        curr = curr + left.length + raw.length;
                        // console.log(`\t left: '${left}' -- curr: '${curr}' -- raw: ${raw} -- stem: '${JSON.stringify(stem)}'`);

                        els.push(left);
                        els.push(makelink(stem.word, raw, samepage));
                    }
                });
            });

            if (curr == 0) {
                // there were no words that matched so just put the whole text in
                els.push(text);
            } else if (curr < text.length) {
                // there is text leftover that we need to append
                els.push(text.substring(curr, text.length));
            }
        }
        return els;
    };

    return pipe(
        allGlossaryEntries(),
        TE.map((es) => es.map(toWordStem)),
        TE.map(linkFromStems),
    );

    // const els: (string | JSX.Element)[] = [];
    // const stems = (await allGlossaryEntries()).map((e) => {
    //     return <WordStem>{
    //         word: e.word,
    //         stem: PorterStemmer.stem(e.word),
    //     };
    // });

    // if (text != undefined && text !== null && (text as string).length > 0) {
    //     let curr = 0;
    //     const tokens = new WordTokenizer().tokenize(text);
    //     tokens.forEach((t, i) => {
    //         const stemmed = PorterStemmer.stem(t);
    //         const raw = tokens[i];
    //         //  console.log(`t: '${t}' -- i: '${i}' -- stemmed: '${stemmed}' -- raw: '${raw}'`);
    //         stems.forEach((stem) => {
    //             if (stem.stem === stemmed) {
    //                 const left = text.substring(curr, text.indexOf(raw, curr));
    //                 curr = curr + left.length + raw.length;
    //                 // console.log(`\t left: '${left}' -- curr: '${curr}' -- raw: ${raw} -- stem: '${JSON.stringify(stem)}'`);

    //                 els.push(left);
    //                 els.push(makelink(stem.word, raw, samepage));
    //             }
    //         });
    //     });

    //     if (curr == 0) {
    //         // there were no words that matched so just put the whole text in
    //         els.push(text);
    //     } else if (curr < text.length) {
    //         // there is text leftover that we need to append
    //         els.push(text.substring(curr, text.length));
    //     }
    // }

    // return els;
}

/**
 * All of the Glossary entries with the definitions linked.
 */
export const entriesWithLinkedDefs = (): TaskEither<Error, readonly EntryLinked[]> => {
    const linkEntry = (e: Entry) => (def: string): EntryLinked => {
        return {
            ...e,
            linkedDefinition: def,
        };
    };

    const linkEntries = (es: Entry[]): TaskEither<Error, EntryLinked>[] => {
        return es.map((e) => {
            // eslint-disable-next-line prettier/prettier
            const foo = pipe(
                linkTextFromGlossary(e.definition, true),
                TE.map(serialize),
                TE.map(linkEntry(e)),
            );

            return foo;
        });
    };

    // eslint-disable-next-line prettier/prettier
    const foo = pipe(
        allGlossaryEntries(),
        TE.map(linkEntries),
        // deal with the fact that we have a TE<Error, LinkedEntry>[] but want a TE<Error, LinkedEntry[]>
        TE.map(TE.sequenceArray),
        TE.flatten,
    );

    return foo;
};
