#!/usr/bin/env node
// Offline 3D preview: renders a worldsim export to PNGs with three.js in headless Chromium (no Studio).
//
//   npm install --prefix tools/preview          (once: three + playwright-core; no browser download)
//   lune run tools/worldsim/export.luau candy build/candy.json
//   node tools/preview/render.mjs build/candy.json build/candy        -> build/candy-overview.png, ...
//   node tools/preview/render.mjs build/candy.json build/candy --shots plaza,plots
//   node tools/preview/render.mjs build/candy.json build/candy --cam 0,80,200:0,10,60:50
//
//   lune run tools/worldsim/exportCreatures.luau build/lineup.json rarity:Mythic
//   node tools/preview/render.mjs build/lineup.json build/lineup     -> front, threeQuarter, back, side, top
//
// Options: --shots a,b (presets below), --cam x,y,z:tx,ty,tz[:fov] (repeatable), --size 1280x720, --cell 4
// (terrain voxel size), --no-shadows, --no-fog, --labels (creature names over a lineup).
// The browser is Playwright's Chromium; set CHROMIUM_PATH if it isn't at the default location below.

import { chromium } from "playwright-core";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
if (args.length < 2) {
	console.error("usage: node tools/preview/render.mjs <scene.json> <outPrefix> [--shots a,b] [--cam x,y,z:tx,ty,tz[:fov]]");
	process.exit(1);
}
const [scenePath, outPrefix] = args;
const flag = (name) => args.includes(name);
const option = (name) => {
	const i = args.indexOf(name);
	return i >= 0 ? args[i + 1] : undefined;
};
const allOptions = (name) => args.flatMap((a, i) => (a === name ? [args[i + 1]] : []));

const data = JSON.parse(fs.readFileSync(scenePath, "utf8"));
const [w, h] = (option("--size") || "1280x720").split("x").map(Number);

// World shots: plots x -142..142 and |z| 30..124, belt x -151..151, lobby at x 199, wall x -251..259 and |z| <= 160,
// landmarks outside the wall (Config/Scenery, Config/Gameplay).
const WORLD = {
	overview: { pos: [0, 330, 430], target: [0, 0, 10], fov: 55 },
	aerial: { pos: [20, 700, 2], target: [20, 0, 0], fov: 62 },
	plaza: { pos: [285, 42, 80], target: [199, 6, 0], fov: 55 },
	plots: { pos: [-70, 46, 185], target: [0, 4, 70], fov: 60 },
	belt: { pos: [-60, 24, -36], target: [40, 3, 0], fov: 60 },
	south: { pos: [0, 95, 360], target: [0, 25, 210], fov: 62 },
	north: { pos: [0, 95, -360], target: [0, 25, -210], fov: 62 },
	west: { pos: [-470, 120, 0], target: [-240, 20, 0], fov: 62 },
	east: { pos: [520, 110, 0], target: [290, 20, 0], fov: 62 },
};

function creatureShots() {
	let minX = Infinity, maxX = -Infinity, maxY = 0, maxZ = 0;
	for (const p of data.parts) {
		const r = Math.max(...p.size) / 2;
		minX = Math.min(minX, p.cf[0] - r);
		maxX = Math.max(maxX, p.cf[0] + r);
		maxY = Math.max(maxY, p.cf[1] + r);
		maxZ = Math.max(maxZ, Math.abs(p.cf[2]) + r);
	}
	const cx = (minX + maxX) / 2, cy = maxY * 0.45;
	const span = Math.max(maxX - minX, maxY * 1.6, 6);
	const d = span * 0.95 + maxZ * 2 + 4;
	return {
		front: { pos: [cx, cy + span * 0.12, -d], target: [cx, cy, 0], fov: 40 },
		threeQuarter: { pos: [cx + d * 0.55, cy + span * 0.35, -d * 0.8], target: [cx, cy, 0], fov: 40 },
		back: { pos: [cx, cy + span * 0.12, d], target: [cx, cy, 0], fov: 40 },
		side: { pos: [maxX + d * 0.9, cy + span * 0.1, 0], target: [maxX - Math.min(span, 8) / 2, cy, 0], fov: 40 },
		top: { pos: [cx, d * 1.1, -d * 0.25], target: [cx, 0, 0], fov: 40 },
	};
}

const isLineup = Array.isArray(data.labels);
const presets = isLineup ? creatureShots() : WORLD;
const shots = [];
const wanted = option("--shots");
for (const name of wanted ? wanted.split(",") : Object.keys(presets)) {
	if (!presets[name]) {
		console.error(`unknown shot ${name}; presets: ${Object.keys(presets).join(", ")}`);
		process.exit(1);
	}
	shots.push({ name, ...presets[name] });
}
allOptions("--cam").forEach((spec, i) => {
	const [pos, target, fov] = spec.split(":");
	shots.push({ name: `cam${i + 1}`, pos: pos.split(",").map(Number), target: target.split(",").map(Number), fov: Number(fov) || 55 });
});
if (isLineup && flag("--labels")) {
	for (const s of shots) s.labels = data.labels.map((l) => ({ text: l.name, at: [l.x, l.height + 0.8, 0] }));
}

const executablePath = process.env.CHROMIUM_PATH || "/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell";
const browser = await chromium.launch({
	executablePath,
	args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--allow-file-access-from-files"],
});
const page = await browser.newPage({ viewport: { width: w, height: h } });
page.on("console", (m) => { if (m.type() === "error") console.error("page:", m.text()); });
page.on("pageerror", (e) => console.error("page error:", e.message));
await page.goto("file://" + path.join(here, "scene.html"));
await page.waitForFunction(() => window.previewReady === true);
const options = {
	size: [w, h],
	cell: Number(option("--cell")) || 4,
	shadows: !flag("--no-shadows"),
	fog: !flag("--no-fog"),
	shadowMap: isLineup ? 2048 : 4096,
};
const started = Date.now();
const results = await page.evaluate(({ data, shots, options }) => window.renderShots(data, shots, options), { data, shots, options });
fs.mkdirSync(path.dirname(path.resolve(outPrefix)), { recursive: true });
for (const r of results) {
	const file = `${outPrefix}-${r.name}.png`;
	fs.writeFileSync(file, Buffer.from(r.url.split(",")[1], "base64"));
	console.log(`wrote ${file}`);
}
console.log(`${results.length} shot(s), ${data.parts.length} parts in ${((Date.now() - started) / 1000).toFixed(1)} s`);
await browser.close();
