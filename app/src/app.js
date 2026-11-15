'use strict';

const path = require('path');
const fs = require('fs');
const express = require('express');
const helmet = require('helmet');
const { createStore } = require('./store');

const FONT_DIRS = {
  'space-grotesk': path.dirname(require.resolve('@fontsource/space-grotesk/package.json')),
  'jetbrains-mono': path.dirname(require.resolve('@fontsource/jetbrains-mono/package.json')),
};

// Scan summary is mounted by Kubernetes from a ConfigMap the pipeline creates.
const summaryPath = () => process.env.SCAN_SUMMARY_PATH || '/config/scan-summary.json';

function readScanSummary() {
  try {
    return JSON.parse(fs.readFileSync(summaryPath(), 'utf8'));
  } catch {
    return null; // running locally / outside the pipeline
  }
}

function buildInfo() {
  return {
    app: 'ShipGuard',
    version: process.env.APP_VERSION || require('../package.json').version,
    build: process.env.BUILD_NUMBER || 'local',
    commit: process.env.GIT_COMMIT || 'dev',
    image: process.env.IMAGE_TAG || 'shipguard:local',
    environment: process.env.APP_ENV || 'local',
    deployedAt: process.env.DEPLOYED_AT || null,
    pod: process.env.HOSTNAME || 'localhost',
  };
}

function createApp({ store = createStore() } = {}) {
  const app = express();
  app.disable('x-powered-by');

  // Strict security headers — these are what keep OWASP ZAP quiet.
  app.use(
    helmet({
      contentSecurityPolicy: {
        useDefaults: false,
        directives: {
          defaultSrc: ["'self'"],
          scriptSrc: ["'self'"],
          styleSrc: ["'self'"],
          fontSrc: ["'self'"],
          imgSrc: ["'self'", 'data:'],
          connectSrc: ["'self'"],
          objectSrc: ["'none'"],
          baseUri: ["'self'"],
          formAction: ["'self'"],
          frameAncestors: ["'none'"],
        },
      },
      crossOriginEmbedderPolicy: true,
      hsts: false, // TLS is terminated outside the pod; enable at the ingress/LB
    })
  );
  app.use((req, res, next) => {
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()');
    if (req.path.startsWith('/api/')) res.setHeader('Cache-Control', 'no-store');
    next();
  });

  app.use(express.json({ limit: '10kb' }));

  // ---- API ----
  app.get('/healthz', (req, res) => res.json({ status: 'ok' }));
  app.get('/readyz', (req, res) => res.json({ status: 'ready' }));

  app.get('/api/info', (req, res) => res.json(buildInfo()));
  app.get('/api/scans', (req, res) => res.json(readScanSummary() || { source: 'none' }));

  app.get('/api/releases', (req, res) => res.json(store.list()));

  app.post('/api/releases', (req, res) => {
    const { title, severity } = req.body || {};
    const result = store.add({ title, severity });
    if (result.error) return res.status(400).json({ error: result.error });
    return res.status(201).json(result.item);
  });

  app.delete('/api/releases/:id', (req, res) => {
    const ok = store.remove(req.params.id);
    return ok ? res.status(204).end() : res.status(404).json({ error: 'not found' });
  });

  // ---- Static frontend ----
  app.use('/fonts/space-grotesk', express.static(path.join(FONT_DIRS['space-grotesk'], 'files'), { maxAge: '30d' }));
  app.use('/fonts/jetbrains-mono', express.static(path.join(FONT_DIRS['jetbrains-mono'], 'files'), { maxAge: '30d' }));
  app.use(express.static(path.join(__dirname, '..', 'public'), { maxAge: '1h' }));

  app.use('/api', (req, res) => res.status(404).json({ error: 'not found' }));
  app.use((req, res) => res.status(404).type('text/plain').send('Not found'));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    const status = err.status || 500;
    if (status >= 500) console.error(JSON.stringify({ level: 'error', msg: err.message, path: req.path }));
    res.status(status).json({ error: status === 500 ? 'internal error' : err.message });
  });

  return app;
}

module.exports = { createApp, buildInfo, readScanSummary };
