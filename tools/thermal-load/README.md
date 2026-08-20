# Thermal Load

This local macOS tool creates a controlled, bounded CPU and Metal GPU workload for tuning Fan Control's automatic-response settings.

## Build

```bash
./build.sh
```

## Run the default plan

```bash
./thermal-load
```

The default four-minute plan is:

1. 30 seconds at 15% CPU / 0% GPU;
2. 60 seconds at 60% CPU / 0% GPU;
3. 60 seconds at 65% CPU / 45% GPU;
4. 90 seconds at 15% CPU / 0% GPU.

The tool limits CPU to 80% and GPU to 70%. Stop it at any time with Control-C.

## Custom plan

Each step is `seconds:cpu:gpu`:

```bash
./thermal-load --plan "30:15:0,60:60:0,60:65:45,90:15:0"
```

Keep Fan Control visible during the test. A useful initial configuration is a 1-second ramp-up and a 10-second ramp-down; observe whether the RPM changes are stable at the transitions between the CPU and CPU+GPU steps.
