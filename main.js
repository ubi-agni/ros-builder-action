// All actions use the same (but differently named) .js file
// eventually calling src/scripts/generic.sh and passing the
// name of the action extracted from the .js file name.
// This is needed as we can't pass arguments from action.yaml

'use strict'
const fs = require('fs')
const child_process = require('child_process')
const core = require('@actions/core')
const ps = require('ps-node')

// find paths of generic.sh and action .sh script
function script_paths() {
  // extract basename of current source file
  var name = __filename.split('/').pop().split('.').shift()

  // traverse up to root folder of project (containing main.js)
  var path = __dirname
  do {
    if (fs.existsSync(path + '/main.js')) {
      break
    }
    path = path.split('/').slice(0, -1).join('/')
  } while (true)
  return [path + '/src/scripts/generic.sh', __dirname + '/' + name + '.sh']
}

var [generic, action] = script_paths()
var child = child_process.spawn(generic, [action], { stdio: 'inherit' })

function forward(signal) {
  child.kill(signal)

  ps.lookup({ ppid: child.pid }, function (err, resultList) {
    if (err) { throw new Error(err) }
    resultList.forEach(function (p) {
      try { process.kill(p.pid, signal) } catch (error) { }
    })
  })
}
function handle(signal) {
  console.log('[33mForwarding signal ' + signal + ' to child process[0m')
  forward(signal)
}
// kill child (and sub processes) on signals SIGINT and SIGTERM
process.on('SIGINT', handle)
process.on('SIGTERM', handle)

// exit if child exits
child.on('exit', function (exit_code, signal) {
  const expect = core.getInput('EXPECT_EXIT_CODE') || 0 // expected exit code
  exit_code = exit_code !== null ? exit_code : 130
  const suffix = exit_code == expect ? ' (as expected)' : ' != ' + expect
  const msg = 'Process finished with code ' + exit_code + suffix
  exit_code == expect ? core.debug(msg) : core.warning(msg)
  process.exit(exit_code == expect ? 0 : 1)
})

// cancel build after given timout (github default: 6h - 20min slack)
const timeout_minutes = core.getInput('BUILD_TIMEOUT') || (6 * 60 - 20)
function cancel() {
  console.log('')
  core.warning('Cancelling build due to timeout')
  forward('SIGINT')
  // escalate to SIGTERM after 5s
  // https://github.com/ringerc/github-actions-signal-handling-demo
  setTimeout(function () { forward('SIGTERM') }, 5 * 1000)
}
setTimeout(cancel, timeout_minutes * 60 * 1000)
