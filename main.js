// All actions use the same (but differently named) .js file
// eventually calling src/scripts/generic.sh and passing the
// name of the action extracted from the .js file name.
// This is needed as we can't pass arguments from action.yaml

'use strict';
const fs = require('fs');
const child_process = require('child_process');

// find paths of generic.sh and action .sh script
function script_paths() {
  // extract basename of current source file
  var name = __filename.split('/').pop().split('.').shift();

  // traverse up to root folder of project (containing main.js)
  var path = __dirname;
  do {
    if (fs.existsSync(path + '/main.js')) {
      break;
    }
    path = path.split('/').slice(0, -1).join('/');
  } while (true);
  return [path + '/src/scripts/generic.sh', __dirname + '/' + name + '.sh'];
}

var [generic, action] = script_paths();
var child = child_process.spawn(generic, [action], { stdio: 'inherit' });

// kill child on signals SIGINT and SIGTERM
function handle(signal) {
  console.log('[33mForwarding signal ' + signal + ' to child process[0m');
  // Escalate signal INT -> TERM -> KILL
  // https://github.com/ringerc/github-actions-signal-handling-demo
  if (signal == 'SIGINT') { signal = 'SIGTERM'; }
  else if (signal == 'SIGTERM') { signal = 'SIGKILL'; }
  child.kill(signal);
}
process.on('SIGINT', handle);
process.on('SIGTERM', handle);

// keep process running
setInterval(function () { }, 10000);

// exit if child exits
child.on('exit', function (exit_code, signal) {
  exit_code = exit_code !== null ? exit_code : (128 + 9);
  console.log('Process finished with code ' + exit_code);
  process.exit(exit_code);
});
