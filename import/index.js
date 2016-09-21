var chokidar = require('chokidar');
var async = require('async');
var exec = require('child_process').exec;
var spawn = require('child_process').spawn;
var FUSED_DIR = process.env.FUSED_DIR;
var ENC_DATA_DIR = process.env.ENC_DATA_DIR;
var KEY = process.env.KEY;
var ENCRYPT_PW = process.env.ENCRYPT_PW;
var DEC_DATA_DIR = process.env.DEC_DATA_DIR;
var options = {
  ignored: [
    /[\/\\]\._/,
    /[\/\\]\.DS_Store/,
    /[\/\\]\.TemporaryItems/,
    /[\/\\]\.unionfs-fuse/,
    /[\/\\]_HIDDEN~/,
  ],
  // TODO scale stability threshold on filesize if possible?
  // NOTE: FILES THAT DO NOT EXIST ON DISK FOR AT LEAST 10s WILL NOT BE IN BACKUP
  awaitWriteFinish: { stabilityThreshold: 10000, pollInterval: 100 }
};

// startup ssh for sshfs mounting. this sucks.
exec('service ssh start');

var running = {};
function removeEmptyFileRefs() {
  paths = Object.keys(running);
  for (var i = 0; i<paths.length; i++) {
    path = paths[i];
    if (!running[path].length) {
      delete running[path];
    }
  }
}

// create a queue object with concurrency 1000
var q = async.queue(function(task, callback) {
  console.log('(' + task.filename +
    ') ::: starting task "' + task.name + ' ' + task.args.join(' ') + '"');
  var cmd = spawn(task.name, task.args);

  var realpath = task.realpath;
  running[realpath] = running[realpath] || [];
  running[realpath].push({ cmd: cmd, realpath: realpath });

  cmd.stdout.on('data', function (data) {
    console.log('(' + task.filename + ') :stdout: ' + data.toString().trim());
  });
  cmd.stderr.on('data', function (data) {
    console.log('(' + task.filename + ') :stderr: ' + data.toString().trim());
  });
  cmd.on('exit', function (code) {
    removeEmptyFileRefs();
    foobar(callback, task);
  });
// task queue is potentially the upper limit on number of concurrent acd uploads
// TODO remove deletes from this process scheduling task array
}, 1000);

function log(filename, message) {
  console.log('(' + filename + ') : ' + message);
}
function logger(e, o, r, filename) {
  if (o) { log(filename, 'stdout: ' + o.trim()); }
  if (r) { log(filename, 'stderr: ' + r.trim()); }
  if (e) {
    if (e && !r) { log(filename, 'error: ' + e); }
    return;
  }
}

function foobar(callback, task) {
  return function (error, stdout, stderr) {
    exec('acd_cli sync', function (e,o,r) {
      var filename = task.filename;
      logger(task.error,task.stdout,task.stderr,filename);
      logger(error,stdout,stderr,filename);
      logger(e,o,r, filename);
      callback();

      log(filename, task.event + 'ed file:\t' + task.path + ' @ ' + task.realpath);

      // # Once the file is uploaded, we don't need to keep it locally anymore
      exec('rm -r ' + DEC_DATA_DIR + '/' + filename);
      exec('rm -r ' + task.realpath);
    })
  }
}

// One-liner for current directory, ignores .dotfiles
chokidar.watch([FUSED_DIR], options).on('all', onAllChanges);

function onAllChanges(event, path, details) {
  var filename = path.split('/').slice(2).join('/');
//log(filename, '(' + event + ') - ' + path);
  var filesize = details && details.size && (details.size + 'bytes ');
  var cmd = 'ENCFS6_CONFIG="' + KEY + '" encfsctl encode ' + '--extpass="' +
    ENCRYPT_PW + '" ' + ENC_DATA_DIR + ' "/'+filename+'"';

    log(filename, event + ' ' + path);
  if (event !== 'add' && event !== 'addDir' && event !== 'change' && event !== 'unlink' && event !== 'unlinkDir') {
    return;
  }

  exec(cmd, function (error, stdout, stderr) {
    var encodedir = stdout.trim();
    var realpath = ENC_DATA_DIR + '/' + encodedir;

    if (event === 'change' || event === 'add' || event === 'addDir') {
      var directory = event === 'addDir' ? realpath.split('/').slice(0,-1).join('/') : realpath;
      var cmd, args;
      if (event === 'addDir') {
        cmd = 'mkdir';
        args = ['-p', directory];
      } else {
        cmd = 'acd_cli';
        args = ['upload', directory, '/'];
      }

      // add an item to the queue
      var task = { name: cmd, args: args, event: event, path: path, realpath: realpath };
      task.filename = filename; task.error = error; task.stdout = stdout; task.stderr = stderr;
      var argsJoined = task.args.join(' ');
      if (filename) {
        log(filename, filesize + '::: adding task "' + task.name + ' ' + argsJoined + '"');

        q.push(task, function(err) {
          if (err) { console.log(err); }
          log(filename, filesize + '::: finished processing', event, path, realpath);
          log(filename, filesize + '::: adding task "' + task.name + ' ' + argsJoined + '"');
        });
      }
    } else if (event === 'unlink' || event === 'unlinkDir') {
      log(filename, 'Removing file @ ' + realpath);

      // # this will 'error' if the file does not exist locally
      exec('rm -r "' + DEC_DATA_DIR + '/"' + filename, function () {
        exec('rm -r "' + realpath + '"', function () {
            running[realpath] = running[realpath] || [];
            running[realpath].forEach(function (cmd) {
if (cmd.realpath === realpath) {
cmd.cmd.stdin.pause();
cmd.cmd.kill();
}
            });
          exec('acd_cli rm "/' + encodedir + '"', function (error, stdout, stderr) {
            logger(error,stdout,stderr,filename);
            log(filename, 'upstream removal complete.');
          });
        });
      });
    }
  });
}
