// PM2 process file — runs the Node and Python services on the VPS.
// Usage (as the CloudPanel site user, from the project root):
//   pm2 start ecosystem.config.cjs && pm2 save
module.exports = {
  apps: [
    {
      name: 'happybasic-node',
      cwd: __dirname + '/services/node',
      script: 'src/server.mjs',
      interpreter: 'node',
      autorestart: true,
      max_memory_restart: '300M',
      out_file: __dirname + '/storage/logs/node.out.log',
      error_file: __dirname + '/storage/logs/node.err.log',
    },
    {
      name: 'happybasic-python',
      cwd: __dirname + '/services/python',
      script: 'src/server.py',
      // Uses the venv if present, else system python3.
      interpreter: require('fs').existsSync(__dirname + '/services/python/.venv/bin/python')
        ? __dirname + '/services/python/.venv/bin/python'
        : 'python3',
      autorestart: true,
      max_memory_restart: '300M',
      env: { PYTHONUNBUFFERED: '1' },
      out_file: __dirname + '/storage/logs/python.out.log',
      error_file: __dirname + '/storage/logs/python.err.log',
    },
  ],
};
