'use strict';

const crypto = require('crypto');

const SEVERITIES = ['info', 'low', 'medium', 'high'];
const MAX_ITEMS = 50;

// Simple in-memory store for release notes. Swap for DynamoDB/RDS later if you like.
function createStore(seed = defaultSeed()) {
  let items = [...seed];

  return {
    list: () => [...items].sort((a, b) => b.createdAt.localeCompare(a.createdAt)),

    add({ title, severity = 'info' }) {
      if (typeof title !== 'string' || !title.trim()) return { error: 'title is required' };
      const clean = title.trim();
      if (clean.length > 120) return { error: 'title must be 120 characters or fewer' };
      if (!SEVERITIES.includes(severity)) return { error: `severity must be one of ${SEVERITIES.join(', ')}` };

      const item = { id: crypto.randomUUID(), title: clean, severity, createdAt: new Date().toISOString() };
      items.push(item);
      if (items.length > MAX_ITEMS) items = items.slice(-MAX_ITEMS);
      return { item };
    },

    remove(id) {
      const before = items.length;
      items = items.filter((i) => i.id !== id);
      return items.length < before;
    },
  };
}

function defaultSeed() {
  const now = Date.now();
  return [
    { id: crypto.randomUUID(), title: 'Pinned base image to node:24-alpine digest', severity: 'medium', createdAt: new Date(now - 3600e3 * 26).toISOString() },
    { id: crypto.randomUUID(), title: 'Added strict Content-Security-Policy', severity: 'high', createdAt: new Date(now - 3600e3 * 5).toISOString() },
    { id: crypto.randomUUID(), title: 'Container now runs as non-root, read-only FS', severity: 'low', createdAt: new Date(now - 3600e3).toISOString() },
  ];
}

module.exports = { createStore, SEVERITIES };
