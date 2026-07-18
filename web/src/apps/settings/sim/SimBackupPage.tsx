import { useCallback, useEffect, useState } from 'react';

import { t } from '@/i18n';
import { fetchNui, isFiveM } from '@/core/nui';
import { formatPhone } from '@/lib/phone';
import { useNuiEvent } from '@/hooks/useNuiEvent';
import { AlertDialog } from '@/ui/AlertDialog';
import { ListGroup, ListRow, ToggleRow } from '@/ui/ListGroup';
import { SubPage } from '../SettingsSubPage';

interface SimInfo {
    mode: 'container' | 'metadata';
    hasSim: boolean;
    number?: string;
    ejectable: boolean;
    backupOn: boolean;
    backupEnabled: boolean;
    canRestore: boolean;
}

type Envelope<T> = { success: boolean; data?: T; message?: string };

const DEV_INFO: SimInfo = {
    mode: 'metadata', hasSim: true, number: '2075550149',
    ejectable: true, backupOn: true, backupEnabled: false, canRestore: true,
};

/** Settings -> SIM & Backup (unique-phones mode): SIM status, eject, cloud backup + restore. */
export function SimBackupPage({ onBack }: { onBack: () => void }) {
    const [info,    setInfo]    = useState<SimInfo | null>(null);
    const [busy,    setBusy]    = useState(false);
    const [confirm, setConfirm] = useState<'eject' | 'restore' | null>(null);
    const [notice,  setNotice]  = useState<string | null>(null);

    const load = useCallback(async () => {
        if (!isFiveM) { setInfo(DEV_INFO); return; }
        const res = await fetchNui<Envelope<SimInfo>>('sd-phone:sim:get').catch(() => null);
        if (res?.success && res.data) setInfo(res.data);
    }, []);

    useEffect(() => { void load(); }, [load]);
    useNuiEvent('sd-phone:simState', useCallback(() => { void load(); }, [load]));

    async function toggleBackup() {
        if (!info || busy) return;
        setBusy(true);
        const res = await fetchNui<Envelope<never>>('sd-phone:sim:backup:set', { on: !info.backupEnabled }).catch(() => null);
        setBusy(false);
        if (res?.success) setInfo({ ...info, backupEnabled: !info.backupEnabled });
        else if (res?.message) setNotice(res.message);
    }

    async function eject() {
        setConfirm(null);
        if (busy) return;
        setBusy(true);
        const res = await fetchNui<Envelope<never>>('sd-phone:sim:eject').catch(() => null);
        setBusy(false);
        if (!res?.success && res?.message) setNotice(res.message);
        void load();
    }

    async function restore() {
        setConfirm(null);
        if (busy) return;
        setBusy(true);
        const res = await fetchNui<Envelope<{ rows: number }>>('sd-phone:sim:backup:restore').catch(() => null);
        setBusy(false);
        if (res?.success) setNotice(t('settings.simRestoreDone', 'Backup restored. Reopen your apps to see the data.'));
        else if (res?.message) setNotice(res.message);
        void load();
    }

    const number = info?.number ? formatPhone(info.number) : '—';

    return (
        <>
            <SubPage title={t('settings.simBackup', 'SIM & Backup')} onBack={onBack}>
                <ListGroup footer={info?.mode === 'container'
                    ? t('settings.simFooterContainer', 'Your number lives on the SIM card in this phone. Open the phone in your inventory to swap the SIM.')
                    : t('settings.simFooterMetadata', 'Your number lives on the SIM card installed in this phone. Use a SIM card item to install it.')}>
                    <ListRow
                        label={t('settings.simStatus', 'SIM Status')}
                        value={info === null ? '…' : (info.hasSim ? t('settings.simInstalled', 'Installed') : t('settings.simNone', 'No SIM'))}
                        divider
                    />
                    <ListRow label={t('settings.myNumber', 'My Number')} value={info?.hasSim ? number : '—'} divider={!!info?.ejectable} />
                    {info?.ejectable && (
                        <ListRow
                            label={t('settings.simEject', 'Eject SIM Card')}
                            destructive
                            onPress={() => setConfirm('eject')}
                        />
                    )}
                </ListGroup>

                {info?.backupOn && (
                    <ListGroup footer={t('settings.simBackupFooter', 'Cloud Backup belongs to your character, not the phone. With backup on, getting a new phone and SIM lets you restore your data — the phone number stays with the old SIM.')}>
                        <ToggleRow
                            label={t('settings.simCloudBackup', 'Cloud Backup')}
                            on={info.backupEnabled}
                            onToggle={() => { void toggleBackup(); }}
                            divider={info.canRestore}
                        />
                        {info.canRestore && (
                            <ListRow
                                label={t('settings.simRestore', 'Restore from Backup')}
                                onPress={() => setConfirm('restore')}
                            />
                        )}
                    </ListGroup>
                )}
            </SubPage>

            {confirm === 'eject' && (
                <AlertDialog
                    title={t('settings.simEjectTitle', 'Eject SIM Card?')}
                    message={t('settings.simEjectMessage', 'The SIM card returns to your inventory and this phone loses service until a SIM is installed again.')}
                    confirmLabel={t('settings.simEjectConfirm', 'Eject')}
                    destructive
                    onCancel={() => setConfirm(null)}
                    onConfirm={() => { void eject(); }}
                />
            )}

            {confirm === 'restore' && (
                <AlertDialog
                    title={t('settings.simRestoreTitle', 'Restore from Backup?')}
                    message={t('settings.simRestoreMessage', 'Your backed-up messages, contacts, photos and settings will be copied onto this phone. Your number stays the one on the current SIM.')}
                    confirmLabel={t('settings.simRestoreConfirm', 'Restore')}
                    onCancel={() => setConfirm(null)}
                    onConfirm={() => { void restore(); }}
                />
            )}

            {notice && (
                <AlertDialog
                    title={t('settings.simBackup', 'SIM & Backup')}
                    message={notice}
                    confirmLabel={t('common.ok', 'OK')}
                    hideCancel
                    onCancel={() => setNotice(null)}
                    onConfirm={() => setNotice(null)}
                />
            )}
        </>
    );
}
