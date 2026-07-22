import { useEffect, useRef, useState } from 'react';
import { ChevronLeft, Lock } from 'lucide-react';

import { useIosPush } from '@/hooks/useIosPush';
import { t } from '@/i18n';
import { MAX_TEXT_LENGTH, type DocFile } from './data';

interface Props {
    doc:       DocFile;
    backLabel: string;
    onBack:    () => void;
    onSave:    (content: string) => void;
    animateIn?: boolean;
}

export function TextEditor({ doc, backLabel, onBack, onSave, animateIn = true }: Props) {
    const { goBack, pageStyle } = useIosPush(onBack, animateIn);

    const [body, setBody] = useState(doc.content ?? '');
    const locked = doc.locked;

    const lastSaved = useRef(doc.content ?? '');
    const onSaveRef = useRef(onSave);
    onSaveRef.current = onSave;

    useEffect(() => {
        if (locked) return;
        const handle = window.setTimeout(() => {
            if (body === lastSaved.current) return;
            lastSaved.current = body;
            onSaveRef.current(body);
        }, 800);
        return () => window.clearTimeout(handle);
    }, [body, locked]);

    // Flush on unmount (covers back before the debounce fires). Refs hold latest.
    const live = useRef(body);
    live.current = body;
    useEffect(() => () => {
        if (locked) return;
        if (live.current !== lastSaved.current) {
            lastSaved.current = live.current;
            onSaveRef.current(live.current);
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, []);

    return (
        <div
            className="absolute inset-0 z-30 flex flex-col bg-white dark:bg-base text-black dark:text-white"
            style={pageStyle}
        >
            <div className="h-[58px] shrink-0" aria-hidden />

            <div className="flex items-center gap-2 px-2 pb-1 pt-3">
                <button
                    type="button"
                    onClick={goBack}
                    className="flex shrink-0 items-center gap-0.5 text-ios-blue active:opacity-60"
                >
                    <ChevronLeft className="h-[26px] w-[26px]" strokeWidth={2.5} />
                    <span className="text-[17px]">{backLabel}</span>
                </button>
                <span className="min-w-0 flex-1 truncate text-center text-[17px] font-semibold">{doc.name}</span>
                <span className="flex w-[68px] shrink-0 items-center justify-end pr-1.5">
                    {locked && (
                        <span className="flex items-center gap-1 text-[13px] text-ios-gray">
                            <Lock className="h-[14px] w-[14px]" strokeWidth={2.4} />
                            {t('documents.readOnly', 'Read Only')}
                        </span>
                    )}
                </span>
            </div>

            <div className="flex-1 overflow-y-auto no-scrollbar px-4">
                <textarea
                    value={body}
                    readOnly={locked}
                    maxLength={MAX_TEXT_LENGTH}
                    onChange={e => setBody(e.target.value)}
                    placeholder={t('documents.startWriting', 'Start writing…')}
                    className="mt-4 w-full resize-none bg-transparent text-[17px] leading-snug outline-none placeholder:text-ios-gray"
                    style={{ minHeight: 320 }}
                    aria-label={t('documents.documentBody', 'Document body')}
                />
            </div>

            <div className="flex shrink-0 items-center justify-center px-4 pb-12 pt-2">
                <span className="text-[13px] text-ios-gray tabular-nums">
                    {t('documents.charCount', '{n} of {max} characters', { n: body.length, max: MAX_TEXT_LENGTH })}
                </span>
            </div>
        </div>
    );
}
