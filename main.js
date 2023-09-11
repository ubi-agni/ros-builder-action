// All actions use the same (but differently named) .js file
// eventually calling src/scripts/generic.sh and passing the
// name of the action extracted from the .js file name.
// This is needed as we can't pass arguments from action.yaml

'use strict';

// find paths of generic.sh and action .sh script
function script_paths() {
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
  return [path + '/src/scripts/generic.sh', __dirname + '/' + name + '.sh'];
}

var [generic, action] = script_paths();
var child = require('child_process').spawn(generic, [action], { stdio: 'inherit' });

// kill child on signals SIGINT and SIGTERM
function handle(signal) {
  child.kill(signal);
}
process.on('SIGINT', handle);
process.on('SIGTERM', handle);

// keep process running
setInterval(function () { }, 10000);

// exit if child exits
child.on('exit', function (exit_code, signal) {
  process.exit(exit_code !== null ? exit_code : 143);
});
