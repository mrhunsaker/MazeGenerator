```ps1
Get-ChildItem -Path ./mazes -Filter *.bpm | ForEach-Object {
    $outputName = $_.BaseName + "_traced.svg"
    $outputPath = Join-Path $_.DirectoryName $outputName
    potrace -s -o $outputPath $_.FullName
}
```

```bash
for f in *.bmp; do potrace -s -o "${f%.png}_traced.svg" "$f"; done
```