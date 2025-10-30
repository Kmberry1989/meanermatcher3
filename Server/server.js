import { WebSocketServer } from 'ws';

const PORT = process.env.PORT || 9090;
const wss = new WebSocketServer({ port: PORT });

// Rooms: code -> { clients: Set(ws), ready: Set(ws), ids: Map(ws->id) }
const rooms = new Map();
const matchmakingQueues = new Map(); // mode -> [ws]
let nextClientId = 1;

function send(ws, obj) {
  try { ws.send(JSON.stringify(obj)); } catch (_) {}
}

function broadcast(room, obj, exceptWs = null) {
  const txt = JSON.stringify(obj);
  for (const c of room.clients) {
    if (c !== exceptWs && c.readyState === c.OPEN) {
      c.send(txt);
    }
  }
}

function genCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let s = '';
  for (let i = 0; i < 4; i++) s += chars[Math.floor(Math.random() * chars.length)];
  return s;
}

function roomOf(ws) {
  for (const [code, room] of rooms) {
    if (room.clients.has(ws)) return [code, room];
  }
  return [null, null];
}

function removeFromQueues(ws) {
  for (const queue of matchmakingQueues.values()) {
    const index = queue.indexOf(ws);
    if (index > -1) {
      queue.splice(index, 1);
    }
  }
}

wss.on('connection', (ws) => {
  const id = String(nextClientId++);
  send(ws, { type: 'welcome', id });

  ws.on('message', (data) => {
    let msg = {};
    try { msg = JSON.parse(data.toString()); } catch (_) { return; }
    const t = msg.type;
    if (t === 'find_match') {
      const mode = msg.mode || 'coop';
      if (!matchmakingQueues.has(mode)) {
        matchmakingQueues.set(mode, []);
      }
      const queue = matchmakingQueues.get(mode);
      queue.push(ws);
      if (queue.length >= 2) {
        const [p1, p2] = queue.splice(0, 2);
        let code;
        do { code = genCode(); } while (rooms.has(code));
        rooms.set(code, { clients: new Set(), ready: new Set(), ids: new Map() });
        const room = rooms.get(code);
        room.clients.add(p1);
        room.clients.add(p2);
        room.ids.set(p1, String(nextClientId++));
        room.ids.set(p2, String(nextClientId++));
        send(p1, { type: 'match_found', code });
        send(p2, { type: 'match_found', code });
      }
    }
    else if (t === 'cancel_match') {
      removeFromQueues(ws);
    }
    else if (t === 'join_room') {
      const code = (msg.code || '').toString().toUpperCase();
      const room = rooms.get(code);
      if (!room) return;
      room.clients.add(ws);
      room.ids.set(ws, id);
      send(ws, { type: 'room_joined', code, id });
      // Send current state to joiner
      const players = Array.from(room.ids.values());
      send(ws, { type: 'room_state', players });
      broadcast(room, { type: 'player_joined', id }, ws);
    }
    else if (t === 'leave_room') {
      const [code, room] = roomOf(ws);
      if (!room) return;
      room.clients.delete(ws);
      room.ready?.delete(ws);
      const pid = room.ids.get(ws);
      room.ids.delete(ws);
      broadcast(room, { type: 'player_left', id: pid });
      if (room.clients.size === 0) rooms.delete(code);
    }
    else if (t === 'ready') {
      const [code, room] = roomOf(ws);
      if (!room) return;
      room.ready.add(ws);
      if (room.ready.size === room.clients.size && room.clients.size > 0) {
        broadcast(room, { type: 'start_game', mode: 'coop', seed: Date.now() });
      }
    }
    else if (t === 'start_game') {
      const [, room] = roomOf(ws);
      if (!room) return;
      const payload = { ...msg, type: 'start_game' };
      if (!payload.seed) payload.seed = Date.now();
      if (!payload.mode) payload.mode = 'coop';
      broadcast(room, payload);
    }
    else if (t === 'state') {
      const [, room] = roomOf(ws);
      if (!room) return;
      const pid = room.ids.get(ws) || id;
      broadcast(room, { type: 'state', id: pid, x: msg.x, y: msg.y }, ws);
    }
    else if (t === 'game') {
      const [, room] = roomOf(ws);
      if (!room) return;
      const pid = room.ids.get(ws) || id;
      const payload = { ...msg, id: pid };
      broadcast(room, payload);
    }
  });

  ws.on('close', () => {
    removeFromQueues(ws);
    const [code, room] = roomOf(ws);
    if (!room) return;
    room.clients.delete(ws);
    room.ready?.delete(ws);
    const pid = room.ids.get(ws);
    room.ids.delete(ws);
    broadcast(room, { type: 'player_left', id: pid });
    if (room.clients.size === 0) rooms.delete(code);
  });
});

console.log(`Simple WS server on port ${PORT}`);
