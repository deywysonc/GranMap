import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

// Relative drawing coordinates, not surveyed metres. The PDF supplies the
// upper room proportions; author corrections supply the ground topology.
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const map = JSON.parse(readFileSync(resolve(root, 'app/assets/maps/gran_tiete_upper_floorplan_v11.json'), 'utf8'));
map.building.version = '0.12-floorplan-v12';
Object.assign(map.metadata, {
  geometryStatus: 'floorplan_relative',
  mapMode: 'architectural_floorplan_with_provisional_ground',
  surveyStatus: 'upper_pdf_and_author_spatial_corrections_v12',
  importantNote: 'Piso superior baseado nas proporções da planta, com grande espaço caminhável abaixo da galeria, Agronomia à esquerda da rampa e caminhos livres pela área ampla conforme informações do autor. Térreo esquemático: lanchonete à esquerda e rampa logo à direita, ambas de frente à quadra com acesso pelo sul e circulação compartilhada. Dois conjuntos de Laboratórios de Química junto da entrada não representam quantidade ou nomes oficiais de salas. Posições, limites e novos atalhos são aproximados, sem portas ou acessibilidade aferidas; escala e distâncias exigem conferência presencial.',
});
map.floors[0].name = 'Térreo';
map.floors[1].name = 'Piso superior';
const nodes = new Map(map.nodes.map(node => [node.id, node]));
const pois = new Map(map.pois.map(poi => [poi.id, poi]));
const oldZones = new Map(map.zones.map(zone => [zone.id, zone]));
const zones = [];
function zone(id, name, type, floor, x, y, width, height, verification = 'user_reported') {
  zones.push({ id, name, type, floor, x, y, width, height, verification,
    evidenceCaptureIds: oldZones.get(id)?.evidenceCaptureIds ?? [] });
}
function display(id, x, y) {
  const node = nodes.get(id);
  if (!node) throw new Error(`Missing node ${id}`);
  node.displayX = x;
  node.displayY = y;
}
function node(id, floor, x, y, displayX, displayY, type = 'corridor') {
  const value = { id, floor, x, y, z: floor, type, displayX, displayY };
  map.nodes.push(value);
  nodes.set(id, value);
}
function edge(from, to, distance, type = 'corridor', verification = 'floorplan', accessible = true) {
  map.edges.push({ from, to, distance, type, accessible, verification, evidenceCaptureIds: [] });
}

// Facing inward from Entrada Gran: classrooms are on the left; the small
// ramped room is on the right of the bend, not the multi-floor ramp.
zone('zone_ground_c1', 'Corredor Gran', 'corridor_gran', 0, 24, 66, 80, 8, 'observed_video');
zone('zone_ground_gran_entry', 'Entrada Gran', 'corridor_gran', 0, 4, 74, 13, 8, 'user_confirmed');
zone('zone_ground_gran_bend', 'Acesso Gran', 'corridor_gran', 0, 16, 66, 10, 16, 'user_confirmed');
display('ground_c1_start', 8, 78);
display('ground_c1_first', 16, 78);
display('ground_c1_turn', 24, 70);
display('ground_c1_room_ramp', 26, 60);
nodes.get('ground_c1_room_ramp').y = 26;
zone('zone_ground_ramped_room', 'Sala com rampa', 'classroom', 0, 21, 52, 10, 11, 'user_confirmed');
zone('zone_ground_ramped_room_access', 'Acesso à sala', 'corridor_gran', 0, 24, 63, 4, 3, 'user_confirmed');
const granRoomIds = ['lab_quimica', 'lab_microscopia', 'lab_informatica', 'clinica_escola', 'leonardo_da_vinci', 'isaac_newton'];
for (let i = 0; i < granRoomIds.length; i++) {
  const poi = pois.get(granRoomIds[i]);
  const cx = 40 + i * 11.5;
  display(`ground_c1_door_${i}`, cx, 76);
  nodes.get(`ground_c1_door_${i}`).y = 42;
  zone(`zone_ground_${poi.id}`, poi.name, poi.type, 0, cx - 5.75, 74, 11.5, 18);
}

// The author marked two groups, not a surveyed count of individual rooms.
// Unique full names also keep zone selection tied to the correct group.
const chemistryGroups = [
  ['labs_quimica_entrada_gran', 'Laboratórios de Química na Entrada Gran',
    'ground_labs_quimica_entrada', 'zone_ground_labs_quimica_entrada',
    'Entrada Gran · conjunto aproximado', 4, 83, 22, 8],
  ['labs_quimica_sala_rampa', 'Laboratórios de Química próximos à sala com rampa',
    'ground_labs_quimica_rampa', 'zone_ground_labs_quimica_rampa',
    'Ao lado da sala com rampa · conjunto aproximado', 0, 54, 13, 10],
];
for (const [id, name, navigationNode, zoneId, sector, x, y, width, height] of chemistryGroups) {
  const poi = { id, name, type: 'laboratory', sector, floor: 0, z: 0,
    navigationNode, verification: 'user_reported_approximate', evidenceCaptureIds: [] };
  map.pois.push(poi);
  pois.set(id, poi);
  zone(zoneId, name, 'laboratory', 0, x, y, width, height, 'user_reported_approximate');
}
node('ground_labs_quimica_entry_approach', 0, 7, 32, 15, 78);
node('ground_labs_quimica_entrada', 0, 7, 38, 15, 84, 'service');
node('ground_labs_quimica_ramp_corner', 0, 8, 32, 18, 70);
node('ground_labs_quimica_ramp_approach', 0, 8, 22, 18, 59);
node('ground_labs_quimica_rampa', 0, 4, 22, 12, 59, 'service');
zone('zone_ground_labs_quimica_link', 'Acesso aproximado aos laboratórios',
  'corridor_gran', 0, 16, 57, 4, 9, 'access_unverified');
zone('zone_ground_labs_quimica_crosslink', 'Acesso aproximado aos laboratórios',
  'corridor_gran', 0, 13, 57, 7, 4, 'access_unverified');
// Provisional access edges deliberately do not assert a real door or an
// accessible route. Keep them distinct from confirmed ramp/corridor segments.
for (const [from, to, distance] of [
  ['ground_c1_start', 'ground_labs_quimica_entry_approach', 6],
  ['ground_labs_quimica_entry_approach', 'ground_labs_quimica_entrada', 6],
  ['ground_c1_turn', 'ground_labs_quimica_ramp_corner', 8],
  ['ground_labs_quimica_ramp_corner', 'ground_labs_quimica_ramp_approach', 10],
  ['ground_labs_quimica_ramp_approach', 'ground_labs_quimica_rampa', 4],
]) edge(from, to, distance, 'provisional_access', 'access_unverified', false);

// Parallel Tyto corridor; rooms alternate on both sides, Secretaria by entry.
zone('zone_ground_c2', 'Corredor Tyto · Secretaria', 'corridor_tyto', 0, 4, 24, 100, 8, 'observed_video');
zone('zone_ground_secretaria', 'Secretaria', 'administration', 0, 4, 32, 9.5, 14, 'user_confirmed');
display('ground_secretaria_door', 8.75, 39);
const tytoIds = ['alan_turing', 'cora_coralina', 'henry_ford', 'albert_einstein', 'socrates', 'karl_marx', 'peter_drucker', 'paulo_freire', 'carlos_drummond', 'zilda_arns', 'maria_lacerda', 'rachel_de_queiroz'];
for (let i = 0; i < tytoIds.length; i++) {
  const poi = pois.get(tytoIds[i]);
  const cx = 20 + i * 7;
  zone(`zone_ground_${poi.id}`, poi.name, poi.type, 0, cx - 6.5, i % 2 === 0 ? 32 : 10, 13, 14);
}

// The circulation goes AROUND the sports court, never through its playing area.
zone('zone_ground_court_west', 'Circulação', 'open_area', 0, 106, 18, 7, 56, 'user_confirmed');
zone('zone_ground_court_north', 'Frente compartilhada da quadra, lanchonete e rampa',
  'open_area', 0, 104, 64, 41, 13, 'user_reported_approximate');
zone('zone_ground_court_south', 'Circulação', 'open_area', 0, 113, 18, 32, 5, 'user_confirmed');
zone('zone_ground_court_east', 'Circulação', 'open_area', 0, 138, 23, 7, 44, 'user_confirmed');
zone('zone_ground_court', 'Quadra', 'court', 0, 115, 24, 22, 40, 'user_confirmed');
zone('zone_ground_snack', 'Lanchonete', 'cafeteria', 0, 115, 77, 10, 15, 'user_reported_approximate');
zone('zone_ground_upper_access', 'Rampa · subir', 'ramp', 0, 126, 77, 11, 15, 'user_reported_approximate');
pois.get('lanchonete').sector = 'De frente à quadra · fim do Corredor Gran';
for (const [id, x, y] of [
  ['ground_court_west_north', 110, 70], ['ground_court_west_mid', 110, 44],
  ['ground_court_west_south', 110, 20], ['ground_court_east_north', 141, 70],
  ['ground_court_east_south', 141, 20], ['ground_snack_bar', 120, 78],
  ['ground_spiral_ramp_landing', 131.5, 78], ['ground_ramp_run_1', 131.5, 83],
  ['ground_ramp_landing_mid', 131.5, 88],
]) display(id, x, y);
// The former narrow ramp-approach zone is merged into the broad court front.
node('ground_ramp_access_corner', 0, 124, 34, 131.5, 70);
node('ground_snack_front', 0, 96, 34, 120, 70, 'open_area');
map.edges = map.edges.filter(item =>
  !(item.from === 'ground_c1_end' && item.to === 'ground_spiral_ramp_landing'));
edge('ground_c1_end', 'ground_ramp_access_corner', 34, 'ramp_access', 'user_confirmed');
edge('ground_ramp_access_corner', 'ground_spiral_ramp_landing', 26, 'ramp_access', 'user_confirmed');
edge('ground_court_west_north', 'ground_snack_front', 10, 'open_area', 'access_unverified', false);
edge('ground_snack_front', 'ground_ramp_access_corner', 11.5, 'open_area', 'access_unverified', false);
// Preserve the existing arrival edge as the cafeteria's only connection.
// A second link through its indoor anchor would create a shortcut through
// the cafeteria on journeys to the ramp. The shared front stays separate.

const services = [
  ['biblioteca', 'ground_services_north', 52, 59, 30],
  ['financeiro', 'ground_services_mid', 37, 44, 23],
  ['banheiros', 'ground_services_south', 22, 28.5, 16],
];
for (const [poiId, id, bottom, cy, navY] of services) {
  const poi = pois.get(poiId);
  zone(`zone_ground_${poiId}`, poi.name, poi.type, 0, 145, bottom, 14, 13, 'user_confirmed');
  display(id, 147, cy);
  node(`${id}_approach`, 0, 122, navY, 141, cy);
  edge(`${id}_approach`, id, 2, 'door', 'user_confirmed');
}
map.edges = map.edges.map(item => {
  if (services.some(([, id]) => item.from === id)) item.from += '_approach';
  if (services.some(([, id]) => item.to === id) && item.type !== 'door') item.to += '_approach';
  return item;
});
// Keep each new door attached to its destination, not the approach itself.
for (const [, id] of services) {
  const door = map.edges.find(item => item.from === `${id}_approach` && item.type === 'door');
  door.to = id;
}

// PDF relative proportions: top at74, main room frontage at54.5.
// Right-hand laboratories and final classroom have shallower depth(9.8).
zone('zone_upper_corridor', 'Galeria superior', 'corridor_upper', 1, 4, 48.8, 103.5, 5.7, 'floorplan');
zone('zone_upper_corridor_step', 'Galeria', 'corridor_upper', 1, 101.8, 54.5, 5.7, 9.7, 'floorplan_relative');
zone('zone_upper_corridor_right', 'Galeria dos laboratórios', 'corridor_upper', 1, 107.5, 58.5, 44.4, 5.7, 'floorplan_relative');
zone('zone_upper_bwc_access', 'Acesso aos banheiros', 'corridor_upper', 1, 81.4, 54.5, 2.3, 9.8, 'floorplan');
zone('zone_upper_gate', 'Portão Superior', 'upper_entrance', 1, 1, 40, 3, 8, 'user_confirmed');
zone('zone_upper_gate_access', 'Acesso superior', 'corridor_upper', 1, 4, 40, 5, 8.8, 'user_confirmed');
// Latest author labels override the earlier lower-left ramp assumption.
zone('zone_upper_ramp', 'Rampa · descer', 'ramp', 1, 117, 1, 27, 16, 'user_reported_approximate');
// This is a broad walkable space, not a pair of narrow invented corridors.
// Keep it above the separate Arquivo and Agronomia/ramp zones. The right
// continuation fills the shallower laboratories' setback below their gallery.
zone('zone_upper_south_access', 'Espaço amplo caminhável do piso superior',
  'open_area', 1, 4, 17, 147.9, 31.8, 'user_reported_approximate');
zone('zone_upper_ramp_access', 'Continuação do espaço caminhável à direita',
  'open_area', 1, 107.5, 48.8, 44.4, 9.7, 'user_reported_approximate');
const upperRooms = [
  ['van_gogh', 'zone_upper_van_gogh', 4, 13.3, 'classroom', false],
  ['cecilia_meireles', 'zone_upper_cecilia', 17.3, 12.9, 'classroom', false],
  ['lab_kaisen_machado_assis', 'zone_upper_kaisen', 30.2, 12.7, 'laboratory', false],
  ['tarsila_do_amaral', 'zone_upper_tarsila', 42.9, 13, 'classroom', false],
  ['auditorio', 'zone_upper_auditorio', 55.9, 25.5, 'auditorium', false],
  ['monteiro_lobato', 'zone_upper_monteiro', 89.5, 11.9, 'classroom', false],
  ['fayol', 'zone_upper_fayol', 101.4, 18.5, 'laboratory', true],
  ['ayrton_senna', 'zone_upper_ayrton', 119.9, 15.8, 'project_laboratory', true],
  ['santos_dummont', 'zone_upper_santos', 135.7, 16.2, 'classroom', true],
];
for (let i = 0; i < upperRooms.length; i++) {
  const [poiId, zoneId, x, width, type, shallow] = upperRooms[i];
  const bottom = shallow ? 64.2 : 54.5;
  const poi = pois.get(poiId);
  poi.type = type === 'project_laboratory' ? 'laboratory' : type;
  zone(zoneId, poi.name, type, 1, x, bottom, width, 74 - bottom, 'floorplan_relative');
  display(`upper_door_${i}`, x + width / 2, bottom + 1.5);
  display(`upper_spine_${i}`, x + width / 2, shallow ? 61.3 : 51.5);
  nodes.get(`upper_spine_${i}`).y = shallow ? 29 : 25;
  nodes.get(`upper_door_${i}`).y = shallow ? 35 : 31;
}
zone('zone_upper_bwc_fem', 'BWC Feminino', 'restroom', 1, 83.7, 54.5, 5.8, 9.8, 'floorplan');
zone('zone_upper_bwc_masc', 'BWC Masculino', 'restroom', 1, 81.4, 64.3, 8.1, 9.7, 'floorplan');
zone('zone_upper_archive', 'Arquivo', 'archive', 1, 34, 8, 41.6, 5.1, 'floorplan');
zone('zone_upper_agronomy', 'Agronomia', 'agronomy', 1, 84, 1, 25, 16, 'user_reported_approximate');
for (const [id, x, y] of [
  ['upper_gate', 2.5, 44], ['upper_end', 153, 61.3],
  ['upper_service_spine', 82.5, 51.5], ['upper_bwc_fem', 85, 56],
  ['upper_bwc_masc', 84, 65.8], ['upper_archive_approach', 54.8, 51.5],
  ['upper_archive', 54.8, 10.5], ['upper_agronomy', 96.5, 16],
  ['upper_ramp_approach', 130.5, 20], ['upper_ramp_run_2', 130.5, 14],
  ['upper_spiral_ramp', 130.5, 5],
]) display(id, x, y);
node('upper_gallery_turn', 1, 56, 25, 104.7, 51.5);
node('upper_gallery_step', 1, 56, 29, 104.7, 61.3);
node('upper_bwc_passage', 1, 84, 27, 82.5, 62.5);
node('upper_south_access_corner', 1, 56, 18, 104.7, 20);
node('upper_agronomy_approach', 1, 110, 18, 96.5, 20);
node('upper_open_west', 1, 24, 18, 30, 35, 'open_area');
node('upper_open_center', 1, 44, 18, 70, 35, 'open_area');
node('upper_open_east', 1, 76, 18, 115, 35, 'open_area');
// Avoid a diagonal route crossing the Monteiro room: climb the gallery step.
map.edges = map.edges.filter(item =>
  !(item.from === 'upper_spine_5' && item.to === 'upper_spine_6') &&
  !(item.from === 'upper_service_spine' && item.to === 'upper_bwc_masc') &&
  !(item.from === 'upper_ramp_approach' && item.to === 'upper_spine_0') &&
  !(item.from === 'upper_end' && item.to === 'upper_agronomy'));
edge('upper_spine_5', 'upper_gallery_turn', 4.5);
edge('upper_gallery_turn', 'upper_gallery_step', 4);
edge('upper_gallery_step', 'upper_spine_6', 3.5);
edge('upper_service_spine', 'upper_bwc_passage', 2);
edge('upper_bwc_passage', 'upper_bwc_masc', 2, 'door');
// Preserve existing route/closure IDs, with an additional mesh of reasonable
// shortcuts across the author-confirmed walking space. New links do not
// assert surveyed accessibility, doors or real metric lengths.
edge('upper_gallery_turn', 'upper_south_access_corner', 7, 'ramp_access', 'access_unverified');
edge('upper_south_access_corner', 'upper_ramp_approach', 52, 'ramp_access', 'access_unverified');
edge('upper_south_access_corner', 'upper_agronomy_approach', 54, 'outdoor', 'access_unverified');
edge('upper_agronomy_approach', 'upper_agronomy', 12, 'provisional_access', 'access_unverified');
for (const [from, to, distance] of [
  ['upper_spine_0', 'upper_open_west', 11],
  ['upper_spine_2', 'upper_open_west', 9],
  ['upper_archive_approach', 'upper_open_center', 10],
  ['upper_spine_3', 'upper_open_center', 13],
  ['upper_spine_4', 'upper_open_center', 8],
  ['upper_spine_5', 'upper_open_east', 13],
  ['upper_gallery_turn', 'upper_open_east', 10],
  ['upper_spine_6', 'upper_open_east', 15],
  ['upper_spine_8', 'upper_open_east', 20],
  ['upper_open_west', 'upper_open_center', 20],
  ['upper_open_center', 'upper_open_east', 22],
  ['upper_open_center', 'upper_agronomy_approach', 15],
  ['upper_open_east', 'upper_agronomy_approach', 10],
  ['upper_open_east', 'upper_ramp_approach', 11],
  ['upper_open_east', 'upper_south_access_corner', 8],
]) edge(from, to, distance, 'open_area', 'access_unverified', false);

// Preserve XYZ navigation and stable POI IDs. Drawing positions follow their
// graph anchors so selection, routes and PDR markers agree across renderers.
for (const poi of map.pois) {
  const anchor = nodes.get(poi.navigationNode);
  poi.displayX = anchor.displayX;
  poi.displayY = anchor.displayY;
  poi.x = anchor.x;
  poi.y = anchor.y;
}
pois.get('rampa_acesso_sala').name = 'Sala com rampa de acesso';
pois.get('santos_dummont').name = 'Santos Dumont';
zones.find(item => item.id === 'zone_upper_santos').name = 'Santos Dumont';
// The court label belongs inside the playing area; route arrival remains at
// its accessible entrance on the west circulation, rather than on the court.
pois.get('quadra').displayX = 126;
pois.get('quadra').displayY = 44;
map.zones = zones;

const ids = new Set(map.nodes.map(item => item.id));
const edgeIds = new Set();
for (const item of map.edges) {
  if (!ids.has(item.from) || !ids.has(item.to) || item.from === item.to || item.distance <= 0) throw new Error(`Invalid edge ${item.from} ${item.to}`);
  const id = `${item.from}__${item.to}`;
  if (edgeIds.has(id)) throw new Error(`Duplicate ${id}`);
  edgeIds.add(id);
}
writeFileSync(resolve(root, 'app/assets/maps/gran_tiete_floorplan_v12.json'), JSON.stringify(map, null, 2) + '\n', 'utf8');
console.log(`v12: ${map.zones.length} zones, ${map.nodes.length} nodes, ${map.pois.length} POIs`);
