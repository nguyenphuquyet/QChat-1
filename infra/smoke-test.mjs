// Run inside the backend container against the public HTTPS endpoint.
// Creates temporary users, a conversation and a file, then removes only those records.
import assert from 'node:assert/strict';
import { randomBytes, randomUUID } from 'node:crypto';
import { PrismaClient } from '@prisma/client';
import { S3Client, DeleteObjectCommand } from '@aws-sdk/client-s3';
import { io } from 'socket.io-client';

const origin = process.env.WEB_ORIGIN;
assert.ok(origin?.startsWith('https://'));
const db = new PrismaClient();
const s3 = new S3Client({ endpoint: process.env.S3_ENDPOINT,
  region: process.env.S3_REGION, forcePathStyle: true,
  credentials: { accessKeyId: process.env.S3_ACCESS_KEY, secretAccessKey: process.env.S3_SECRET_KEY } });
const users = [];
const suffix = randomUUID().slice(0, 8);
const emails = ['a', 'b'].map(name => `deploy_${name}_${suffix}@example.test`);
let conversation;
let group;
let socket;
const objectKeys = new Set();
async function request(path, method = 'GET', body, token, status = 200) {
  const response = await fetch(`${origin}/api${path}`, {
    method, signal: AbortSignal.timeout(15000),
    headers: { 'Content-Type': 'application/json', Origin: origin,
      ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  assert.equal(response.status, status, `${method} ${path}: HTTP ${response.status}`);
  return response.json();
}
try {
  assert.equal((await request('/health')).ok, true);
  await request('/users/me', 'GET', undefined, undefined, 401);
  for (const [index, email] of emails.entries()) {
    const password = randomBytes(24).toString('base64url');
    const user = await request('/auth/register', 'POST', {
      qchatId: `deploy_${index}_${suffix}`, email, nickname: 'Deployment test', password,
    });
    users.push(user);
    assert.ok((await request('/auth/login', 'POST', { identifier: email, password })).accessToken);
  }
  const [a, b] = users;
  console.log('PASS: HTTPS, database, Redis, registration and login');
  const invitation = await request('/friends/requests', 'POST', { recipientId: b.userId }, a.accessToken);
  await request(`/friends/requests/${invitation.id}`, 'PATCH', { accept: true }, b.accessToken);
  conversation = await request('/conversations', 'POST', { memberIds: [b.userId] }, a.accessToken);
  socket = io(origin, { transports: ['websocket'], auth: { token: b.accessToken }, reconnection: false });
  await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('WebSocket connection timed out')), 15000);
    socket.once('connect', () => { clearTimeout(timeout); resolve(); });
    socket.once('connect_error', error => { clearTimeout(timeout); reject(error); });
  });
  const delivery = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Message delivery timed out')), 15000);
    socket.once('message:new', message => { clearTimeout(timeout); resolve(message); });
  });
  const payload = { clientId: randomUUID(), kind: 'TEXT', text: 'Deployment verification' };
  const message = await request(`/conversations/${conversation.id}/messages`, 'POST', payload, a.accessToken);
  assert.equal((await delivery).id, message.id);
  assert.equal((await request(`/conversations/${conversation.id}/messages`, 'POST', payload, a.accessToken)).id, message.id);
  assert.equal((await request(`/conversations/${conversation.id}/messages`, 'GET', undefined, b.accessToken)).length, 1);
  console.log('PASS: friendship, chat history, WebSocket delivery and send deduplication');

  const bytes = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aXfoAAAAASUVORK5CYII=', 'base64');
  const intent = await request('/media/upload-intent', 'POST', { mime: 'image/png', size: bytes.length, name: 'deployment-test.png' }, a.accessToken);
  const row = await db.media.findUniqueOrThrow({ where: { id: intent.id } });
  objectKeys.add(row.key);
  const upload = await fetch(intent.url, { method: 'PUT', headers: { 'Content-Type': 'image/png', Origin: origin }, body: bytes, signal: AbortSignal.timeout(15000) });
  assert.equal(upload.status, 200, 'Signed media upload');
  const completed = await request('/media/complete', 'POST', { mediaId: intent.id }, a.accessToken);
  objectKeys.add(completed.key);
  const access = await request(`/media/${intent.id}/access`, 'GET', undefined, a.accessToken);
  const download = await fetch(access.url, { signal: AbortSignal.timeout(15000) });
  assert.equal(download.status, 200);
  assert.deepEqual(Buffer.from(await download.arrayBuffer()), bytes);
  const unsigned = new URL(access.url); unsigned.search = '';
  assert.equal((await fetch(unsigned, { signal: AbortSignal.timeout(15000) })).status, 403);
  await request(`/media/${intent.id}/access`, 'GET', undefined, b.accessToken, 403);
  console.log('PASS: private media upload, validation, download and access denial');
  await request('/users/me/avatar', 'POST', { mediaId: intent.id }, a.accessToken);
  assert.equal((await request(`/users/${a.userId}`, 'GET', undefined, b.accessToken)).avatarId, intent.id);
  await request(`/media/${intent.id}/access`, 'GET', undefined, b.accessToken);
  const state = await request(`/conversations/${conversation.id}/state`, 'PATCH', { pinned: true, markedUnread: true }, b.accessToken);
  assert.equal(state.pinned, true);
  assert.equal(state.markedUnread, true);
  await request(`/conversations/${conversation.id}/read`, 'POST', { sequence: message.sequence }, b.accessToken);
  const detail = await request(`/conversations/${conversation.id}`, 'GET', undefined, b.accessToken);
  assert.equal(detail.members.find(m => m.userId === b.userId).markedUnread, false);
  await request(`/conversations/${conversation.id}/history`, 'DELETE', {}, b.accessToken);
  assert.equal((await request(`/conversations/${conversation.id}/messages`, 'GET', undefined, b.accessToken)).length, 0);
  assert.equal((await request(`/conversations/${conversation.id}/messages`, 'GET', undefined, a.accessToken)).length, 1);
  assert.equal((await request('/search?q=Deployment', 'GET', undefined, b.accessToken)).messages.length, 0);
  const image = await request(`/conversations/${conversation.id}/messages`, 'POST', {
    clientId: randomUUID(), kind: 'IMAGE', text: 'image test', mediaId: intent.id,
  }, a.accessToken);
  assert.equal((await request(`/conversations/${conversation.id}/messages`, 'GET', undefined, b.accessToken)).length, 1);
  group = await request('/conversations', 'POST', { kind: 'GROUP', title: 'Temporary group', memberIds: [b.userId] }, a.accessToken);
  const forwarded = await request(`/messages/${image.id}/forward`, 'POST', { conversationId: group.id, clientId: randomUUID() }, b.accessToken);
  assert.equal(forwarded.mediaId, intent.id);
  await request(`/messages/${message.id}/forward`, 'POST', { conversationId: group.id, clientId: randomUUID() }, b.accessToken, 403);
  await request(`/conversations/${group.id}`, 'DELETE', undefined, b.accessToken, 403);
  await request(`/conversations/${group.id}`, 'DELETE', undefined, a.accessToken);
  assert.equal(await db.conversation.count({ where: { id: group.id } }), 0);
  console.log('PASS: avatars, pin/unread, private history clearing, media forwarding and owner-only dissolution');
} finally {
  socket?.disconnect();
  const temporary = await db.user.findMany({ where: { email: { in: emails } }, select: { id: true } });
  const ids = temporary.map(user => user.id);
  const files = await db.media.findMany({ where: { ownerId: { in: ids } } });
  for (const file of files) objectKeys.add(file.key);
  for (const Key of objectKeys) await s3.send(new DeleteObjectCommand({ Bucket: process.env.S3_BUCKET, Key }));
  if (group) await db.conversation.deleteMany({ where: { id: group.id } });
  if (conversation) await db.conversation.deleteMany({ where: { id: conversation.id } });
  await db.outbox.deleteMany({ where: { room: { in: ids.map(id => `user:${id}`) } } });
  await db.media.deleteMany({ where: { ownerId: { in: ids } } });
  await db.user.deleteMany({ where: { id: { in: ids } } });
  await db.$disconnect();
  s3.destroy();
  console.log('Temporary test data removed');
}
