import Foundation

/// Shim Node.js/Electron cho game RPG Maker MV đóng gói bằng Electron.
///
/// Bản port Electron (có `preload.js`, `package.json` khai báo electron) sửa
/// thẳng `rpg_core.js`/plugin để gọi `require('electron')`, `require('fs')`,
/// `process.mainModule.filename`… không kiểm tra `Utils.isNwjs()`. Trong
/// WKWebView không có `require` → ReferenceError mỗi frame và plugin chết giữa
/// chừng (`$dataSystem` null…).
///
/// Shim chỉ bật khi `/package.json` nhắc tới "electron", `js/main.js` gọi
/// `require(` (bản NW.js đã sửa, vd nạp plugin bằng `evalNWBin`), hoặc plugin
/// đang bật gọi thẳng API file của StorageManager — kiểm tra bằng XHR đồng bộ
/// lúc document start. Game MV web/NW.js thường không bị
/// đổi đường lưu save. Khi bật, `Utils.isNwjs()` thành true nên save đi qua
/// `fs` giả:
/// - Đọc: file đã ghi (localStorage, khoá `__gh_fs__<path>`) → file game qua HTTP.
/// - Ghi/xoá: chỉ trong localStorage (file game chỉ đọc; xoá = tombstone).
/// - `readdirSync`: WebDAV PROPFIND của LocalWebServer + file đã ghi.
enum ElectronShim {
    /// Tệp bù cho game RPG Maker, đặt theo đường dẫn tương đối trong game
    /// (vd `js/plugins/ChimakiSpine.js` thay cho `ChimakiSpine.bin` biên dịch
    /// bằng nwjc). Dùng làm `runtimeDirectory`: chỉ được phục vụ khi thư mục
    /// game không có tệp đó.
    static var compatDirectory: URL? {
        Bundle.module.resourceURL?.appendingPathComponent("Runtime/rpgmv", isDirectory: true)
    }

    static let source = #"""
    (function() {
      if (typeof window.require !== 'undefined') return;
      function fetchText(u) {
        try {
          var x = new XMLHttpRequest();
          x.open('GET', u, false);
          x.send();
          return x.status === 200 ? x.responseText : '';
        } catch (e) { return ''; }
      }
      // Plugin desktop (vd NrWindowSizeManager) gọi thẳng API file của
      // StorageManager mà không kiểm tra Utils.isNwjs() → các hàm này require('fs').
      function pluginNeedsNode() {
        var api = /process\.mainModule|StorageManager\.(fs[A-Z]\w*|\w*LocalFile\w*|fileDirectoryPath)\s*\(/;
        var re = /"name"\s*:\s*"([^"]+)"\s*,\s*"status"\s*:\s*true/g, list = fetchText('/js/plugins.js'), m;
        while ((m = re.exec(list))) {
          if (api.test(fetchText(encodeURI('/js/plugins/' + m[1] + '.js')))) return true;
        }
        return false;
      }
      // Bật khi game là bản Electron, bản NW.js đã sửa main.js gọi require,
      // hoặc có plugin cần API file của NW.js.
      if (fetchText('/package.json').indexOf('electron') < 0
          && fetchText('/js/main.js').indexOf('require(') < 0
          && !pluginNeedsNode()) return;

      var PREFIX = '__gh_fs__', DEL = '__gh_fs_del__', DIR = '__gh_fs_dir__';
      var ls = window.localStorage;

      function normalize(p) {
        var parts = String(p).replace(/\\/g, '/').split('/'), out = [];
        for (var i = 0; i < parts.length; i++) {
          var s = parts[i];
          if (!s || s === '.') continue;
          if (s === '..') out.pop(); else out.push(s);
        }
        return '/' + out.join('/');
      }
      // Như Node: giữ "/" cuối (game ghép `localFileDirectoryPath() + 'file'`).
      function keepSlash(p) {
        var n = normalize(p);
        return /[\/]$/.test(String(p)) && n !== '/' ? n + '/' : n;
      }
      var path = {
        sep: '/', delimiter: ':',
        normalize: keepSlash,
        join: function() { return keepSlash(Array.prototype.join.call(arguments, '/')); },
        resolve: function() {
          var acc = '';
          for (var i = 0; i < arguments.length; i++) {
            var a = String(arguments[i]);
            acc = a.charAt(0) === '/' ? a : acc + '/' + a;
          }
          return normalize(acc);
        },
        dirname: function(p) {
          var n = normalize(p), i = n.lastIndexOf('/');
          return i <= 0 ? '/' : n.slice(0, i);
        },
        basename: function(p, ext) {
          var b = normalize(p).split('/').pop();
          return ext && b.slice(-ext.length) === ext ? b.slice(0, -ext.length) : b;
        },
        extname: function(p) {
          var b = normalize(p).split('/').pop(), i = b.lastIndexOf('.');
          return i <= 0 ? '' : b.slice(i);
        },
        relative: function(from, to) { return normalize(to).slice(1); },
        isAbsolute: function(p) { return String(p).charAt(0) === '/'; },
        parse: function(p) {
          var s = String(p), base = path.basename(s), ext = path.extname(s);
          var dir = s.indexOf('/') < 0 ? '' : path.dirname(s);
          return { root: s.charAt(0) === '/' ? '/' : '', dir: dir, base: base, ext: ext, name: ext ? base.slice(0, -ext.length) : base };
        },
        format: function(o) {
          var base = o.base || (o.name || '') + (o.ext || '');
          return o.dir ? o.dir + '/' + base : (o.root || '') + base;
        }
      };
      path.posix = path;

      function url(n) { return encodeURI(n).replace(/#/g, '%23').replace(/\?/g, '%3F'); }
      function enoent(n) {
        var e = new Error("ENOENT: no such file or directory, '" + n + "'");
        e.code = 'ENOENT';
        return e;
      }
      var remoteCache = {};
      function remoteExists(n) {
        if (n in remoteCache) return remoteCache[n];
        var r = false;
        try {
          var x = new XMLHttpRequest();
          x.open('HEAD', url(n), false);
          x.send();
          r = x.status >= 200 && x.status < 300;
          if (!r) r = remoteList(n) !== null;
        } catch (e) {}
        remoteCache[n] = r;
        return r;
      }
      var listCache = {};
      function remoteList(n) {
        if (n in listCache) return listCache[n];
        var names = null;
        try {
          var x = new XMLHttpRequest();
          x.open('PROPFIND', url(n === '/' ? '/' : n + '/'), false);
          x.setRequestHeader('Depth', '1');
          x.send();
          if (x.status === 207) {
            names = [];
            var re = /<D:href>([^<]*)<\/D:href>/g, m, first = true;
            while ((m = re.exec(x.responseText))) {
              if (first) { first = false; continue; }
              var h = m[1].replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/\/$/, '');
              var name = h.slice(h.lastIndexOf('/') + 1);
              try { name = decodeURIComponent(name); } catch (e) {}
              names.push(name);
            }
          }
        } catch (e) {}
        listCache[n] = names;
        return names;
      }
      function localKeys(prefix) {
        var keys = [];
        for (var i = 0; i < ls.length; i++) {
          var k = ls.key(i);
          if (k && k.indexOf(prefix) === 0) keys.push(k.slice(prefix.length));
        }
        return keys;
      }
      function isLocalDir(n) {
        if (ls.getItem(DIR + n) !== null) return true;
        var pre = PREFIX + (n === '/' ? '/' : n + '/');
        for (var i = 0; i < ls.length; i++) { var k = ls.key(i); if (k && k.indexOf(pre) === 0) return true; }
        return false;
      }
      function readText(n) {
        var v = ls.getItem(PREFIX + n);
        if (v !== null) return v;
        if (ls.getItem(DEL + n) !== null) throw enoent(n);
        var x = new XMLHttpRequest();
        x.open('GET', url(n), false);
        x.send();
        if (x.status < 200 || x.status >= 300) throw enoent(n);
        return x.responseText;
      }
      function exists(n) {
        if (ls.getItem(PREFIX + n) !== null || isLocalDir(n)) return true;
        if (ls.getItem(DEL + n) !== null) return false;
        return remoteExists(n);
      }
      function write(n, data) {
        ls.setItem(PREFIX + n, typeof data === 'string' ? data : String(data));
        ls.removeItem(DEL + n);
      }
      function later(cb, err, val) { if (typeof cb === 'function') setTimeout(function() { cb(err || null, val); }, 0); }
      function lastCb(args) { var c = args[args.length - 1]; return typeof c === 'function' ? c : null; }

      var fs = {
        existsSync: function(p) { try { return exists(normalize(p)); } catch (e) { return false; } },
        readFileSync: function(p) { return readText(normalize(p)); },
        writeFileSync: function(p, data) { write(normalize(p), data); },
        appendFileSync: function(p, data) {
          var n = normalize(p), old = '';
          try { old = readText(n); } catch (e) {}
          write(n, old + data);
        },
        unlinkSync: function(p) {
          var n = normalize(p);
          if (!exists(n)) throw enoent(n);
          ls.removeItem(PREFIX + n);
          ls.setItem(DEL + n, '1');
        },
        renameSync: function(from, to) {
          var a = normalize(from);
          write(normalize(to), readText(a));
          ls.removeItem(PREFIX + a);
          ls.setItem(DEL + a, '1');
        },
        mkdirSync: function(p) { ls.setItem(DIR + normalize(p), '1'); },
        readdirSync: function(p) {
          var n = normalize(p), base = n === '/' ? '/' : n + '/', seen = {}, out = [];
          var remote = remoteList(n) || [];
          if (!remote.length && !isLocalDir(n)) throw enoent(n);
          remote.forEach(function(name) { if (ls.getItem(DEL + base + name) === null) seen[name] = 1; });
          localKeys(PREFIX + base).forEach(function(rest) { seen[rest.split('/')[0]] = 1; });
          for (var k in seen) out.push(k);
          return out.sort();
        },
        statSync: function(p) {
          var n = normalize(p);
          if (!exists(n)) throw enoent(n);
          var dir = ls.getItem(PREFIX + n) === null && (isLocalDir(n) || remoteList(n) !== null);
          var v = ls.getItem(PREFIX + n);
          return {
            isDirectory: function() { return dir; },
            isFile: function() { return !dir; },
            size: v !== null ? v.length : 0,
            mtime: new Date(), mtimeMs: Date.now()
          };
        }
      };
      fs.lstatSync = fs.statSync;
      fs.rmdirSync = function(p) { ls.removeItem(DIR + normalize(p)); };
      fs.copyFileSync = function(from, to) { write(normalize(to), readText(normalize(from))); };
      var ASYNC = ['readFile', 'writeFile', 'appendFile', 'unlink', 'rename', 'mkdir', 'readdir', 'stat', 'lstat', 'rmdir', 'copyFile'];
      ASYNC.forEach(function(name) {
        fs[name] = function() {
          var args = Array.prototype.slice.call(arguments), cb = lastCb(args);
          if (cb) args.pop();
          try { later(cb, null, fs[name + 'Sync'].apply(fs, args)); } catch (e) { later(cb, e); }
        };
      });
      fs.exists = function(p, cb) { later(function(_, v) { cb(v); }, null, fs.existsSync(p)); };
      fs.promises = {};
      ASYNC.forEach(function(name) {
        fs.promises[name] = function() {
          var args = arguments;
          return new Promise(function(res, rej) { try { res(fs[name + 'Sync'].apply(fs, args)); } catch (e) { rej(e); } });
        };
      });

      function noop() {}
      var fakeWin = {
        on: function(ev, cb) { window.addEventListener(ev, cb); }, removeListener: noop,
        close: function() {}, focus: noop, show: noop, hide: noop, moveTo: noop, resizeTo: noop,
        showDevTools: noop, closeDevTools: noop, isDevToolsOpen: function() { return false; },
        enterFullscreen: noop, leaveFullscreen: noop, isFullscreen: false, menu: null,
        // Tệp .bin là bytecode V8 do nwjc biên dịch, WebKit không chạy được.
        // Nếu cạnh nó có bản .js cùng tên thì nạp bản đó thay thế.
        evalNWBin: function(frame, binPath) {
          var jsPath = normalize(binPath).replace(/\.bin$/i, '.js');
          var code = ls.getItem(PREFIX + jsPath) === null ? fetchText(url(jsPath)) : '';
          if (!code) {
            console.error('GameHub: ' + normalize(binPath) + ' là bytecode NW.js, iOS không chạy được. '
              + 'Cần bản mã nguồn ' + jsPath + ' đặt cạnh nó.');
            return;
          }
          var s = document.createElement('script');
          s.text = code + '\n//# sourceURL=' + jsPath;
          (document.head || document.documentElement).appendChild(s);
          console.log('GameHub: nạp ' + jsPath + ' thay cho ' + normalize(binPath));
        }
      };
      var nwGui = {
        Window: { get: function() { return fakeWin; } },
        App: { argv: [], quit: noop, closeAllWindows: noop },
        Menu: function() { return { append: noop, createMacBuiltin: noop }; },
        MenuItem: function() { return {}; },
        Shell: { openExternal: function(u) { window.open(u, '_blank'); } }
      };
      var ipcRenderer = {
        send: noop, on: noop, once: noop, removeListener: noop, removeAllListeners: noop,
        sendSync: function() { return false; },
        invoke: function() { return Promise.resolve(null); }
      };
      var electron = { ipcRenderer: ipcRenderer, shell: nwGui.Shell, webFrame: { setZoomFactor: noop } };

      var modules = {
        fs: fs, 'fs-extra': fs, 'graceful-fs': fs, path: path, 'path/posix': path,
        electron: electron, 'nw.gui': nwGui, process: null,
        os: { platform: function() { return 'darwin'; }, homedir: function() { return '/'; }, tmpdir: function() { return '/tmp'; }, EOL: '\n' }
      };
      window.require = function(name) {
        if (modules.hasOwnProperty(name)) return modules[name];
        var e = new Error("Cannot find module '" + name + "'");
        e.code = 'MODULE_NOT_FOUND';
        throw e;
      };
      window.process = {
        platform: 'darwin', arch: 'arm64', argv: [], env: {}, versions: { node: '20.0.0', electron: '30.0.0' },
        mainModule: { filename: '/index.html' }, execPath: '/GameHub',
        cwd: function() { return '/'; }, memoryUsage: function() { return { rss: 0, heapTotal: 0, heapUsed: 0 }; },
        // Emscripten (effekseer.min.js của MZ) thấy `process` → dùng hrtime cho clock.
        hrtime: function(prev) {
          var t = performance.now(), s = Math.floor(t / 1000), ns = Math.round((t % 1000) * 1e6);
          if (prev) { s -= prev[0]; ns -= prev[1]; if (ns < 0) { s--; ns += 1e9; } }
          return [s, ns];
        },
        on: noop, exit: noop, nextTick: function(f) { setTimeout(f, 0); }
      };
      modules.process = window.process;
      window.nw = nwGui;
      window.__dirname = '/';
      window.isElectron = true;
      console.log('GameHub: bật shim Node/Electron (fs → localStorage + file game)');
    })();
    """#
}
