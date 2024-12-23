

### Building

```bash
zig build-exe main.zig -lc -lpcd400 -L. -I.
```

### Channel Configurations

You can change with check document.

| CH | Model   | Measurement | Mode   | Strain Mode | Gage Factor | Range | LPF  | Balance |
|----|---------|-------------|--------|-------------|-------------|-------|------|---------|
| 1  | PCD-400 | ON          | Strain | 1G2W        | 2.00        | 5k    | FLAT | ON      |
| 2  | PCD-400 | ON          | Strain | 1G2W        | 2.00        | 5k    | FLAT | ON      |
| 3  | PCD-400 | ON          | Strain | 1G2W        | 2.00        | 5k    | FLAT | ON      |
| 4  | PCD-400 | ON          | Strain | 1G2W        | 2.00        | 5k    | FLAT | ON      |


### Test

```bash
python kyowa-rx.py --host localhost --port 8000 --channels 4
```
