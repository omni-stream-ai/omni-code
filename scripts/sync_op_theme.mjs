import fs from 'node:fs';

const themePath = process.argv[2] || 'designs/theme.op';
const targetPath = process.argv[3] || 'designs/main.op';
const versionMarker = '"version": "1.0.0",\n';
const childrenMarker = '\n  "children": [';

const theme = fs.readFileSync(themePath, 'utf8');
const target = fs.readFileSync(targetPath, 'utf8');

const themeVersionIndex = theme.indexOf(versionMarker);
const themeChildrenIndex = theme.indexOf(childrenMarker, themeVersionIndex);
if (themeVersionIndex < 0 || themeChildrenIndex < 0) {
  throw new Error(`Could not find token block in ${themePath}`);
}

const tokenBlock = theme.slice(themeVersionIndex + versionMarker.length, themeChildrenIndex);

const targetVersionIndex = target.indexOf(versionMarker);
const targetChildrenIndex = target.indexOf(childrenMarker, targetVersionIndex);
if (targetVersionIndex < 0 || targetChildrenIndex < 0) {
  throw new Error(`Could not find injection point in ${targetPath}`);
}

const updated =
  target.slice(0, targetVersionIndex + versionMarker.length) +
  tokenBlock +
  target.slice(targetChildrenIndex);

if (updated !== target) {
  fs.writeFileSync(targetPath, updated);
}
