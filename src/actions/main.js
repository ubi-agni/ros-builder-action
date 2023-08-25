'use strict';
var { spawnSync } = require('child_process');
var r = spawnSync(__dirname + '/main.sh', { stdio: 'inherit' });
if (r.error) {
  throw r.error;
}
process.exit(r.status !== null ? r.status : 1);
