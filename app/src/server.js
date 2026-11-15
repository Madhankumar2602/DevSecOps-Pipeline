'use strict';

const { createApp } = require('./app');

const PORT = Number(process.env.PORT) || 3000;
const server = createApp().listen(PORT, () => {
  console.log(JSON.stringify({ level: 'info', msg: 'ShipGuard listening', port: PORT }));
});

// Graceful shutdown so Kubernetes rolling updates drop no requests.
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(JSON.stringify({ level: 'info', msg: `received ${sig}, shutting down` }));
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(1), 10000).unref();
  });
}
