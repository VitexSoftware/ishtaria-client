import {execFileSync} from 'node:child_process';
import {readFileSync, writeFileSync, mkdirSync} from 'node:fs';
import {dirname, resolve, basename} from 'node:path';
import {fileURLToPath} from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const [archive, serverPath] = process.argv.slice(2);
if (!archive || !serverPath) throw new Error('Usage: node tools/sync-nature-catalog.mjs ARCHIVE SERVER_CATALOG');
const clientPath = resolve(root, 'assets/world_objects.json');
const client = JSON.parse(readFileSync(clientPath, 'utf8'));
const server = JSON.parse(readFileSync(serverPath, 'utf8'));
const biomes = ['ocean', 'lake', 'river', 'beach', 'grassland', 'forest', 'mountain', 'snow'];
const groups = [
    {match: /^tree_pine/, biomes: ['forest', 'mountain', 'snow'], weight: 5, scale: 4, slope: 0.65, trunk: true},
    {match: /^tree_palm/, biomes: ['beach'], weight: 3, scale: 4, slope: 0.4, trunk: true},
    {match: /^tree_/, biomes: ['forest', 'grassland'], weight: 8, scale: 4, slope: 0.55, trunk: true},
    {match: /^(rock|stone)_tall/, biomes: ['mountain', 'snow'], weight: 4, scale: 6, slope: 1.5},
    {match: /^(rock|stone)_large/, biomes: ['beach', 'grassland', 'forest', 'mountain', 'snow'], weight: 3, scale: 3, slope: 1.5},
    {match: /^(rock|stone)_/, biomes: ['beach', 'grassland', 'forest', 'mountain', 'snow'], weight: 3, scale: 1.5, slope: 1.5},
    {match: /^plant_/, biomes: ['grassland', 'forest'], weight: 3, scale: 2, slope: 0.7},
    {match: /^grass/, biomes: ['grassland', 'forest'], weight: 7, scale: 1, slope: 0.7, passable: true},
    {match: /^flower_/, biomes: ['grassland', 'forest'], weight: 3, scale: 1, slope: 0.7, passable: true},
    {match: /^mushroom_/, biomes: ['forest'], weight: 3, scale: 1, slope: 0.7, passable: true},
    {match: /^stump_/, biomes: ['forest', 'grassland'], weight: 2, scale: 2, slope: 0.55},
    {match: /^log(?:_|$)/, biomes: ['forest'], weight: 2, scale: 2, slope: 0.4},
    {match: /^cactus_/, biomes: ['beach'], weight: 2, scale: 2, slope: 0.4},
];
const files = execFileSync('unzip', ['-Z1', archive], {encoding: 'utf8'}).split('\n')
    .filter(path => /^Models\/GLTF format\/[^/]+\.glb$/.test(path))
    .map(path => ({path, name: basename(path, '.glb')}))
    .map(entry => ({...entry, group: groups.find(group => group.match.test(entry.name))}))
    .filter(entry => entry.group);

function footprint(buffer, trunk) {
    const jsonLength = buffer.readUInt32LE(12);
    const document = JSON.parse(buffer.subarray(20, 20 + jsonLength).toString());
    const binary = 20 + jsonLength + 8;
    const vertices = [];
    function visit(index, parent = position => position) {
        const node = document.nodes[index];
        const transform = position => {
            if (node.matrix) return parent([0, 1, 2].map(axis => node.matrix[12 + axis] + position.reduce((sum, value, column) => sum + value * node.matrix[column * 4 + axis], 0)));
            const scaled = position.map((value, axis) => value * (node.scale?.[axis] ?? 1));
            const quaternion = node.rotation ?? [0, 0, 0, 1];
            const cross = (first, second) => [first[1] * second[2] - first[2] * second[1], first[2] * second[0] - first[0] * second[2], first[0] * second[1] - first[1] * second[0]];
            const first = cross(quaternion, scaled);
            const second = cross(quaternion, first);
            return parent(scaled.map((value, axis) => value + 2 * (quaternion[3] * first[axis] + second[axis]) + (node.translation?.[axis] ?? 0)));
        };
        if (node.mesh !== undefined) {
            for (const primitive of document.meshes[node.mesh].primitives) {
                const accessor = document.accessors[primitive.attributes.POSITION];
                if (accessor.componentType !== 5126 || accessor.type !== 'VEC3' || accessor.sparse) throw new Error('Unsupported positions');
                const view = document.bufferViews[accessor.bufferView];
                for (let vertex = 0; vertex < accessor.count; vertex++) {
                    const position = binary + (view.byteOffset ?? 0) + (accessor.byteOffset ?? 0) + vertex * (view.byteStride ?? 12);
                    vertices.push(transform([0, 1, 2].map(axis => buffer.readFloatLE(position + axis * 4))));
                }
            }
        }
        for (const child of node.children ?? []) visit(child, transform);
    }
    for (const node of document.scenes[document.scene ?? 0].nodes) visit(node);
    if (!vertices.length) throw new Error('Empty model');
    const minimum = Math.min(...vertices.map(position => position[1]));
    const maximum = Math.max(...vertices.map(position => position[1]));
    const solid = trunk ? vertices.filter(position => position[1] <= minimum + (maximum - minimum) * 0.2) : vertices;
    return Math.ceil(Math.max(...solid.map(position => Math.hypot(position[0], position[2]))) * 1000) / 1000;
}

for (const entry of files) {
    const scene = `res://assets/kenney/nature-kit/${entry.path}`;
    if (client.objects.some(item => item.scene === scene)) continue;
    const group = entry.group;
    const buffer = execFileSync('unzip', ['-p', archive, entry.path], {maxBuffer: 16 * 1024 * 1024});
    const radius = group.passable ? 0 : footprint(buffer, group.trunk);
    if (radius * group.scale > 20) throw new Error(`Footprint exceeds API limit: ${entry.name}`);
    const destination = resolve(root, scene.replace('res://', ''));
    mkdirSync(dirname(destination), {recursive: true});
    writeFileSync(destination, buffer);
    const id = `nature.${entry.name}`;
    const weight = Number((group.weight / files.filter(other => other.group === group).length).toFixed(6));
    const common = {id, weight, scale_m: group.scale, max_slope: group.slope};
    client.objects.push({...common, scene, biomes: group.biomes, metallic: 0});
    server.objects.push({...common, biomes: group.biomes.map(name => biomes.indexOf(name)), collision_radius: radius});
}
if (client.objects.length > 256 || client.objects.length !== server.objects.length) throw new Error('Catalog bounds mismatch');
for (const item of client.objects) {
    const peer = server.objects.find(entry => entry.id === item.id);
    if (!peer || ['weight', 'scale_m', 'max_slope'].some(key => peer[key] !== item[key]) || JSON.stringify(peer.biomes.map(index => biomes[index])) !== JSON.stringify(item.biomes)) {
        throw new Error(`Producer/consumer mismatch: ${item.id}`);
    }
}
for (const [path, catalog] of [[clientPath, client], [serverPath, server]]) {
    writeFileSync(path, JSON.stringify(catalog, null, 2) + '\n');
}
console.log(`${files.length} original Nature Kit models, ${client.objects.length} synchronized catalog entries`);