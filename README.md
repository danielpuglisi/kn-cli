# KN CLI

Installation:

```
git clone https://github.com/danielpuglisi/kn-cli.git
cd kn-cli
bundle
```

Usage:

1. Download students CSV from Moodle and save it to `tmp/students-<m223>-<year>.csv`
2. Open the editor
   ```
   bundle exec bin/kn edit tmp/m223-2024.json --curriculum config/223.yml --students tmp/students-m223-2024.csv
   ```
3. Edit the points (changes are autosaved to `tmp/m223-2024.json`)
4. Generate the pdfs
   ```
   bundle exec bin/kn pdf tmp/m223-2024.json --date 27.09.2024 --instructor "Your Name"
   ```
