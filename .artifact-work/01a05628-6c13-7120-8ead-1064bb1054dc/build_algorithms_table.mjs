import fs from "node:fs/promises";
import { SpreadsheetFile, Workbook } from "@oai/artifact-tool";

const outputDir = "/Users/dylanxu/FTC_Event_Scout/outputs/01a05628-6c13-7120-8ead-1064bb1054dc";
const previewPath = `${outputDir}/algorithms_relevance_complexity_preview.png`;
const workbookPath = `${outputDir}/FTC_Event_Scout_Algorithms.xlsx`;

const rows = [
  [
    "Algorithm",
    "Relevance",
    "Complexity",
  ],
  [
    "1. Least-squares OPR estimation with ridge fallback\n\nForms a binary alliance-participation matrix and estimates each team's contribution to total, non-penalty, Auto, Teleop, and Endgame scores.",
    "Very high — This is the project's core calculation. It converts alliance-level match scores into individual team ratings. The ridge fallback keeps results available when the event schedule does not fully constrain every team. (Implemented)",
    "Time: O(mn² + n³), where m is alliance observations and n is teams.\nSpace: O(mn + n²).\nImplementation: High; matrix construction, numerical solving, and rank-deficiency handling are required.",
  ],
  [
    "2. Multi-key comparison sorting\n\nCompares two teams using a selected field, sort direction, missing-value rules, and team number as a deterministic tie-breaker.",
    "Very high — It powers the sortable rankings and OPR charts, letting scouts compare teams by rank, number, total OPR, npOPR, Auto, Teleop, or Endgame performance. (Implemented)",
    "Time: O(n log n).\nSpace: O(n) for the returned sorted collection.\nImplementation: Low–medium; multiple fields, directions, ties, and missing values must be handled consistently.",
  ],
  [
    "3. Hash-map inverted indexing\n\nBuilds mappings such as team number → match history and team number → participation-matrix column.",
    "Very high — A scout can open one team's match history without scanning every match. The same technique also makes OPR matrix construction and team lookups efficient. (Implemented)",
    "Build time: O(ma), where a is the number of teams recorded per match and a ≤ 4.\nLookup: Expected O(1).\nSpace: O(ma).\nImplementation: Low.",
  ],
  [
    "4. Finite-state CSV parsing\n\nReads input one character at a time while tracking whether the parser is inside a quoted field.",
    "High — Match details and calculated OPR values move between the Python backend and Swift app as CSV. Correct handling of quoted commas, escaped quotes, and line endings protects the data pipeline. (Implemented)",
    "Time: O(c), where c is the number of characters.\nSpace: O(c) for the parsed output.\nImplementation: Medium; quoting, escaping, blank rows, and different line endings require care.",
  ],
  [
    "5. Single-pass maximum/argmax with tie retention\n\nTracks the current highest value and replaces or appends matching entries as scores are scanned.",
    "High — It produces the Highlights view for final, non-penalty, Auto, and Teleop alliance scores while preserving every alliance tied for first place. (Implemented)",
    "Time: O(pm), where p = 4 highlight metrics; because p is constant, this is O(m).\nSpace: O(r), where r is the number of tied results.\nImplementation: Low.",
  ],
  [
    "6. Exponentially weighted least squares\n\nExtends OPR by assigning larger weights to recent match observations.",
    "High — It could represent a team's current form more accurately after repairs, driver improvement, or strategy changes, instead of treating its earliest and latest matches equally. (Recommended extension)",
    "Time: O(mn² + n³) with the current dense solver.\nSpace: O(mn + n²).\nImplementation: High; the decay factor, numerical stability, and explanation of the resulting rating must be addressed.",
  ],
  [
    "7. Top-k selection with a min-heap\n\nMaintains only the best k values encountered instead of fully sorting every team.",
    "Medium — The compact charts show only the top 10 teams, so a size-10 heap could generate those summaries efficiently. Full sorting would still be needed for the expanded all-team charts. (Recommended optimization)",
    "Time: O(n log k); with k = 10, this is close to O(n).\nSpace: O(k).\nImplementation: Medium; heap maintenance and deterministic tie-breaking are needed.",
  ],
  [
    "8. K-means clustering\n\nGroups teams by similarity across performance features such as Auto, Teleop, Endgame, npOPR, and consistency.",
    "Medium — It could identify scouting profiles such as Auto specialists, balanced scorers, or Endgame specialists and help scouts find complementary alliance partners. (Recommended extension)",
    "Time: O(ingd), where i is iterations, n is teams, g is clusters, and d is metrics.\nSpace: O(nd + gd).\nImplementation: High; normalization, missing data, cluster selection, and meaningful labels must be handled.",
  ],
];

const workbook = Workbook.create();
const sheet = workbook.worksheets.add("Algorithms");
sheet.showGridLines = false;
sheet.freezePanes.freezeRows(1);

const tableRange = sheet.getRange("A1:C9");
tableRange.values = rows;
tableRange.format = {
  font: { name: "Aptos", size: 11, color: "#172033" },
  verticalAlignment: "top",
  horizontalAlignment: "left",
  wrapText: true,
};

const headerRange = sheet.getRange("A1:C1");
headerRange.format = {
  fill: "#172A46",
  font: { name: "Aptos Display", size: 14, bold: true, color: "#FFFFFF" },
  verticalAlignment: "center",
  horizontalAlignment: "left",
  wrapText: false,
  rowHeight: 32,
  borders: {
    bottom: { style: "medium", color: "#0D1728" },
  },
};

sheet.getRange("A2:C9").format = {
  fill: "#F6F8FB",
  font: { name: "Aptos", size: 11, color: "#172033" },
  verticalAlignment: "top",
  horizontalAlignment: "left",
  wrapText: true,
  borders: {
    insideHorizontal: { style: "thin", color: "#C8D2E0" },
    insideVertical: { style: "thin", color: "#C8D2E0" },
    top: { style: "thin", color: "#A8B6C9" },
    bottom: { style: "medium", color: "#708198" },
    left: { style: "medium", color: "#708198" },
    right: { style: "medium", color: "#708198" },
  },
};

for (const rowNumber of [3, 5, 7, 9]) {
  sheet.getRange(`A${rowNumber}:C${rowNumber}`).format.fill = "#EAF0F7";
}

sheet.getRange("A2:A9").format.font = {
  name: "Aptos",
  size: 11,
  bold: true,
  color: "#102A43",
};

sheet.getRange("A1:A9").format.columnWidth = 47;
sheet.getRange("B1:B9").format.columnWidth = 59;
sheet.getRange("C1:C9").format.columnWidth = 55;
sheet.getRange("A2:C9").format.rowHeight = 116;

const preview = await workbook.render({
  sheetName: "Algorithms",
  range: "A1:C9",
  scale: 1,
  format: "png",
});
await fs.writeFile(previewPath, new Uint8Array(await preview.arrayBuffer()));

const inspection = await workbook.inspect({
  kind: "table",
  range: "Algorithms!A1:C9",
  include: "values,formulas",
  tableMaxRows: 12,
  tableMaxCols: 4,
});
console.log(inspection.ndjson);

const errors = await workbook.inspect({
  kind: "match",
  searchTerm: "#REF!|#DIV/0!|#VALUE!|#NAME\\?|#N/A",
  options: { useRegex: true, maxResults: 100 },
  summary: "final formula error scan",
});
console.log(errors.ndjson);

await fs.mkdir(outputDir, { recursive: true });
const output = await SpreadsheetFile.exportXlsx(workbook);
await output.save(workbookPath);
console.log(JSON.stringify({ workbookPath, previewPath }));
