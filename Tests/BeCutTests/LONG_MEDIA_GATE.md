# Long-media release gate

Run the gate twice before claiming a precise-splitting release is ready: once
with a representative 10-minute source and once with a representative 1-hour
source. Use real H.264/HEVC media at a common shipping resolution, not a tiny
synthetic fixture.

```bash
DEVELOPER_DIR=/Applications/Xcode-26.6-RC.app/Contents/Developer \
BECUT_BENCHMARK_VIDEO=/absolute/path/to/input.mp4 \
BECUT_BENCHMARK_CLASS=10m \
BECUT_BENCHMARK_REPORT=/absolute/path/to/report-10m.json \
xcrun swift test --filter benchmarkRepresentativeLongVideo
```

Use `BECUT_BENCHMARK_CLASS=1h` for the second run. The gate accepts 9–12
minutes for `10m` and 55–65 minutes for `1h`, preventing one file from being
reported as both required classes.

The gate fails if an output is not playable, frame rate or original dimensions
change, a segment differs from its planned duration by more than one source
frame, or peak resident memory reaches 1.5 GB. The JSON report records elapsed
time, peak RSS, output attributes, duration error, and source/output size ratio.
Keep both 10-minute and 1-hour reports with the release evidence.
