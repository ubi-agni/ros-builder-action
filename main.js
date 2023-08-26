// All actions use the same (but differently named) .js file
// eventually calling src/scripts/generic.sh and passing the
// name of the action extracted from the .js file name.
// This is needed as we can't pass arguments from action.yaml

'use strict';
var { spawnSync } = require('child_process');

// extract basename of current source file
var name = __filename.split('/').pop().split('.').shift();

// traverse up to root folder of project (containing main.js)
var path = __dirname;
do {
  if (require('fs').existsSync(path + '/main.js')) {
    break;
  }
  path = path.split('/').slice(0, -1).join('/');
} while (true);

// run generic.sh passing the action .sh script as an argument
var r = spawnSync(path + '/src/scripts/generic.sh',
  [__dirname + '/' + name + '.sh'], { stdio: 'inherit' });

if (r.error) {
  throw r.error;
}
process.exit(r.status !== null ? r.status : 1);
