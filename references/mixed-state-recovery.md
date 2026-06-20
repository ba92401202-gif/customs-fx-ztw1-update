# Mixed-State Recovery

Use this reference when the GC331 to SAP ZTW1 workflow reaches a partial-key state.

## Example Trigger

The OB08 precheck finds some, but not all, target keys:

```text
USD=1, EUR=1, JPY=0, CNY=0
```

This is a stop condition for unattended automation. Continue only when the user explicitly authorizes repairing the missing keys.

## Recovery Pattern

1. Navigate to SAP `OB08`.
2. Choose `New Entries`.
3. Enter only the missing currency rows.
4. Leave existing rows unchanged.
5. Do not directly write `FFACT/TFACT`; let SAP default the conversion ratio.
6. Press Enter and confirm no blocking modal or error remains.
7. Save.
8. Re-enter `OB08`.
9. Position-check all target keys, not only the repaired keys.
10. Compare `KURSP` values numerically against the GC331 `買進` rates.
11. Send the final completion notice with the actual mail message id.

## Evidence To Preserve

Preserve enough evidence to prove source, SAP save, SAP verification, and mail status:

```text
customs_gc331_latest.json
ob08_position_before.txt
ob08_target_counts_before.json
ob08_save_<repair-scope>.txt
ob08_position_after_<repair-scope>.txt
customs_ztw1_update_<valid-from>.txt
```

## Implementation Notes

- If `FFACT/TFACT` controls are visible but not changeable, direct writes may fail with an invalid-argument SAP GUI scripting error.
- If source rates and SAP display differ only by trailing zeros, verify with decimal comparison.
- If the local mail script cannot run because OAuth credentials are absent, use an approved mail connector and record the connector message id in the final notice.
