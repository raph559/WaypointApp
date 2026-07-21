import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const limits = new Map([
  [".css", 300],
  [".jsx", 350],
]);

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const projectDirectory = path.dirname(scriptDirectory);
const sourceDirectory = path.join(projectDirectory, "src");

async function collectFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const files = await Promise.all(
    entries.map(async (entry) => {
      const entryPath = path.join(directory, entry.name);
      return entry.isDirectory() ? collectFiles(entryPath) : entryPath;
    }),
  );

  return files.flat();
}

function countLines(source) {
  if (source.length === 0) return 0;

  const normalized = source.replaceAll("\r\n", "\n").replaceAll("\r", "\n");
  return normalized.split("\n").length - (normalized.endsWith("\n") ? 1 : 0);
}

const authoredFiles = (await collectFiles(sourceDirectory)).filter((file) =>
  limits.has(path.extname(file)),
);

const violations = [];

for (const file of authoredFiles) {
  const extension = path.extname(file);
  const limit = limits.get(extension);
  const lines = countLines(await readFile(file, "utf8"));

  if (lines > limit) {
    violations.push({ file, limit, lines });
  }
}

if (violations.length > 0) {
  console.error("Source-size limits exceeded:");
  for (const { file, limit, lines } of violations) {
    console.error(
      `- ${path.relative(projectDirectory, file)}: ${lines} lines (limit: ${limit})`,
    );
  }
  process.exitCode = 1;
} else {
  console.log(`Source-size check passed for ${authoredFiles.length} files.`);
}
