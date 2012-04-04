#
#  Copyright 2012 Rackspace
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#  limitations under the License.
#


#
# main build file for equus
#
#
#

EnsureSConsVersion(1, 1, 0)
import re
import types
import subprocess
from os.path import join as pjoin
import os
import sys
import fnmatch

p = os.path.join(Dir('#').get_path(), 'site_scons')
if p not in sys.path:
  sys.path.insert(0, p)

p = Dir('#').get_path()
if p not in sys.path:
  sys.path.insert(0, p)

from site_scons import ac
from SCons.Tool import packaging

opts = Variables('build.py')

opts.Add(PathVariable('pubkey',
                      'Path to RSA Public Key code verification.',
                       File("etc/demo.public.key")))

opts.Add('bootstrap_url', default=None, help='Define url ')

opts.Add('branding_name', default='equus', help='Define Branding Name')

opts.Add('branding_url', default='http://www.cloudkick.com', help='Define Branding URL')

opts.Add('branding_support_email',
          default='Cloudkick Support <support@cloudkick.com>',
          help='Define Branding Support String')

opts.Add('branding_short',
          default='host monitoring agent for Cloudkick',
          help='Single line describing the program')

opts.Add('s3_bucket',
          default=None,
          help='s3 bucket path for deploy command.')

opts.Add('use_sigar',
          default=False,
          help='compile in SIGAR support')

opts.Add('branding_long',
          default='The Cloudkick Agent provides monitoring and diagnostics for Cloudkick Users.',
          help='Multiple lines describing the program')

opts.Add(PathVariable('with_openssl',
                      'Prefix to OpenSSL installation', None))


opts.Add(PathVariable('with_mysql',
                      'Prefix to MySQL installation', None))

env = Environment(options=opts,
                  ENV = os.environ.copy(),
                  TARFLAGS = '-c -z',
                  tools=['default', 'subst', 'packaging', 'install', 'jar'])

env['pubkey'] = env.File(env['pubkey'])

packaging.__path__.insert(0, pjoin(env.Dir('#').abspath, 'site_scons', 'site_packaging'))

conf = Configure(env, custom_tests = {'CheckStructOffset': ac.CheckStructOffset,
                                      'CheckUname': ac.CheckUname,
                                      'CheckDpkgArch': ac.CheckDpkgArch})

#TODO: convert this to a configure builder, so it gets cached
def read_version(prefix, path):
  version_re = re.compile("(.*)%s_VERSION_(?P<id>MAJOR|MINOR|PATCH)(\s+)(?P<num>\d+)(.*)" % prefix)
  versions = {}
  fp = open(path, 'rb')
  for line in fp.readlines():
    m = version_re.match(line)
    if m:
      versions[m.group('id')] = int(m.group('num'))
  fp.close()
  return (versions['MAJOR'], versions['MINOR'], versions['PATCH'])

env['version_major'], env['version_minor'], env['version_patch'] = read_version('EQUUS', 'src/equus_version.h')
env['version_string'] = "%d.%d.%d"  % (env['version_major'], env['version_minor'], env['version_patch'])

dvpath = "/etc/debian_version"
if os.path.exists(dvpath):
  contents = open(dvpath).read().strip()
  # TODO: don't hard code this
  if contents == "4.0":
    env['version_string'] += "~bpo40"


cc = conf.env.WhereIs('/Developer/usr/bin/clang')
if os.environ.has_key('CC'):
  cc = os.environ['CC']
if cc:
  conf.env['CC'] = cc

if not conf.CheckFunc('floor'):
  conf.env.AppendUnique(LIBS=['m'])

if conf.CheckDeclaration("__i386__"):
  conf.env['is32bit'] = True
else:
  conf.env['is32bit'] = False

if conf.CheckDeclaration("__amd64__"):
  conf.env['is64bit'] = True
else:
  conf.env['is64bit'] = False

if conf.CheckDeclaration("__ppc__") or conf.CheckDeclaration("__ppc64__"):
  conf.env['isPPC'] = True
else:
  conf.env['isPPC'] = False

if conf.env['is64bit'] == conf.env['is32bit']:
  if conf.env['PLATFORM'] == "win32":
    conf.env['is64bit'] = False
    conf.env['is32bit'] = True
  else:
    print "Your system is messed up.  64bit and 32bit at the same time. b0rk()"
    Exit(1)

# TODO: this is definitely not the ideal way to detect if we are using MSVC
if conf.env['CC'] == "cl":
  conf.env['isMSVC'] = True
else:
  conf.env['isMSVC'] = False

SSL_BIN='openssl'
if conf.env['PLATFORM'] == 'darwin':
  conf.env.Append(CPPDEFINES = {"DARWIN" : 1,
                 "LUA_DL_DYLD": 1,
                 "USE_DLOPEN": 1},
                 CPPPATH=['/usr/include/malloc'])
elif conf.env['PLATFORM'] == "win32":
  SSL_ROOT= "C:/OpenSSL/"
  SSL_BIN = pjoin(SSL_ROOT, 'bin', 'openssl')
  conf.env['SSL_ROOT'] = SSL_ROOT
  conf.env.Append(CPPDEFINES = {"_WIN32": 1, "WIN32": 1, "WINDOWS": 1, "_DEBUG": 1,},
    CPPPATH=[pjoin(SSL_ROOT, "include")])
  if conf.env['isMSVC']:
    conf.env.Append(CFLAGS=['/MTd'], CPPPATH=['#extern/msinttypes'],
                    LIBPATH=[pjoin(SSL_ROOT, "lib", "VC", "static")])
  else:
    conf.env.Append(LIBPATH=[pjoin(SSL_ROOT, "lib", "MinGW")])

  conf.env["use_sigar"] = True

else:
  conf.env.Append(CPPDEFINES = {"LINUX" : 1,
                 "LUA_DL_DLOPEN": 1,
                 "USE_DLOPEN": 1},
                 LIBS=[])

if conf.env['PLATFORM'] == "win32":
  conf.env['EQUUS_PLATFORM'] = "windows_x86"
  conf.env.Append(CPPDEFINES = {"EQUUS_PLATFORM": '\\"%s\\"' % conf.env['EQUUS_PLATFORM']})
else:
  (st, platform) = conf.CheckUname("-sm")
  if not st:
    Exit(-1)
  if platform.lower().find('freebsd') != -1:
    conf.env["PLATFORM"] = 'freebsd'
  if conf.env['is32bit']:
    # stupid 32bit chroots.  uname reports this as a 64bit OS,
    # but everything (except the kernel) is 32bit.
    platform = platform.replace("x86_64", "i386")
  platform = platform.replace("i686", "i386")

  conf.env['EQUUS_PLATFORM'] = platform.replace(" ", "_")

  conf.env.Append(CPPDEFINES = {"EQUUS_PLATFORM": '\\"%s\\"' % conf.env['EQUUS_PLATFORM']})


if conf.env.get('with_openssl'):
  conf.env.AppendUnique(LIBPATH=["${with_openssl}/lib"])
  conf.env.AppendUnique(CPPPATH=["${with_openssl}/include"])

if not conf.CheckCHeader('openssl/evp.h'):
  print 'Missing openssl/evp.h. Install libssl-dev?'
  Exit(-1)

if conf.env.get('with_mysql'):
  conf.env.AppendUnique(CPPPATH=["${with_mysql}/include"])
  conf.env.AppendUnique(CPPPATH=["${with_mysql}/include/mysql5"])

if conf.env['PLATFORM'] == "win32":
  conf.env['MYSQL_HEADER'] = '' # Hack
else:
  if conf.CheckCHeader('mysql/mysql.h'):
    conf.env['MYSQL_HEADER'] = 'mysql/mysql.h'
  else:
    if conf.CheckCHeader('mysql.h'):
      conf.env['MYSQL_HEADER'] = 'mysql.h'
    else:
      print 'Missing mysql/mysql.h. Install mysql-dev?'
      Exit(-1)

if conf.env.get('bootstrap_url'):
  burl = conf.env['bootstrap_url']
  if burl[-1] != '/':
    burl = burl + '/'
  url = burl + conf.env['EQUUS_PLATFORM'] + '/'
  conf.env.Append(CPPDEFINES = {"EQUUS_BOOTSTRAP_URL" : '\\"'+ url + '\\"'})
  conf.env['LOCAL_DEV'] = False
else:
  print "WARNING: Compiling for local development, not using HTTP Bootstrap."
  conf.env.Append(CPPDEFINES = {"LOCAL_DEV" : 1})
  conf.env['LOCAL_DEV'] = True

if conf.env.WhereIs('dpkg'):
  conf.env['HAVE_DPKG'] = True
  (st, env['debian_arch']) = conf.CheckDpkgArch()
  if not st:
    Exit(-1)
else:
  conf.env['debian_arch'] = conf.env['EQUUS_PLATFORM']

if conf.env.WhereIs('light.exe'):
  conf.env['HAVE_WIX'] = True
else:
  conf.env['HAVE_WIX'] = False

# Only do these on Gentoo
if conf.env.WhereIs('emerge'):
  conf.env['HAVE_EMERGE'] = True
  if conf.CheckDeclaration("__i386__"):
    platform = 'i386'
  elif conf.CheckDeclaration("__amd64__"):
    platform = 'amd64'
  else:
    Exit()
  conf.env['gentoo_arch'] = platform
  if os.path.exists("/etc/engineyard/release"):
    conf.env['gentoo_arch'] = "engineyard_" + conf.env['gentoo_arch']

if not conf.env.Detect(['swig']):
  print 'swig is required to build equus'
  Exit(-1)

env = conf.Finish()


def locate(pattern, root=os.curdir):
    '''Locate all files matching supplied filename pattern in and below
    supplied root directory.'''
    for path, dirs, files in os.walk(os.path.abspath(root)):
        for filename in fnmatch.filter(files, pattern):
            yield os.path.join(path, filename)

site_files = []
site_files.extend(env.Glob("site_scons/*/*.py"))
site_files.extend(env.Glob("site_scons/*.py"))
site_files.extend(env.Glob("src/*.h"))
site_files.extend(env.Glob("build.py"))
site_files.extend(locate('*', 'extern'))
env.Depends('.', site_files)


if env['isMSVC']:
  env.AppendUnique(LDFLAGS=['-debug:full', '/DEBUG'],
                   CFLAGS=['/Od', '/RTC1', '/Zi', ])
else:
  env.AppendUnique(CFLAGS=['-Wall', '-ggdb', '-O0'])

env.AppendUnique(CPPPATH="#extern/lua/src")
# TODO: twiddle more bits on util

appname = env.get('branding_name')
Export("appname env")

subst = {}

substkeys = Split("""
branding_name
branding_support_email
branding_url
branding_short
branding_long
version_string
version_major
version_minor
version_patch
debian_arch""")

for x in substkeys:
    subst['%' + str(x) + '%'] = str(env.get(x))

# TODO: Support debug/release builds
extern = SConscript("extern/SConscript")
Export("extern")

installed = []
targets = []

agent = SConscript("src/SConscript")
abin = agent[0][0]
atest = agent[1][0]
shortname = os.path.basename(abin.get_abspath())

env['eqtest'] = atest
tests = SConscript("tests/SConscript")
env.Alias('test', tests)

env['PACKAGEROOT'] = "%s-%s" % (env['branding_name'], env['version_string'])
if env["PLATFORM"] != "win32":
  abin.PACKAGING_INSTALL_LOCATION = pjoin('/usr', 'sbin', shortname)
  #installed.append(env.Install(pjoin('/usr', 'sbin'), agent[0][0]))
else:
  #installed.append(env.Install(pjoin(env['PACKAGEROOT'], 'bin'), agent[0]))
  pass

targets.extend(agent)
targets.extend(installed)

if env["PLATFORM"] == "win32":
  p = env.MSVSProject(target=appname + env['MSVSPROJECTSUFFIX'],
      runfile=targets[0],
      buildtarget=targets[0],
      variant=['Debug'] * len(targets[0])
    )
  targets.extend(p)

equus_rc = env.SubstFile('src/equus.rc.in', SUBST_DICT = subst)

deb_control = env.SubstFile('packaging/debian.control.in', SUBST_DICT = subst)

deb_conffiles = env.SubstFile('packaging/debian.conffiles.in', SUBST_DICT = subst)

deb_init = env.SubstFile('packaging/debian.init.in', SUBST_DICT = subst)

deb_logrotate = env.SubstFile('packaging/debian.logrotate.in', SUBST_DICT = subst)

rh_init = env.SubstFile('packaging/redhat.init.in', SUBST_DICT = subst)

deb_postinst = env.SubstFile('packaging/debian.postinst.in', SUBST_DICT = subst)

deb_prerm = env.SubstFile('packaging/debian.prerm.in', SUBST_DICT = subst)

target_packages = []
pkgbase = "%s-%s" % (env['branding_name'], env['version_string'])
if env["PLATFORM"] != "win32":
  man = env.SubstFile('docs/equus.8.in', SUBST_DICT = subst)
  mangz = env.Command('docs/'+env['branding_name']+'.8.gz', man, "gzip -c $SOURCE > $TARGET")

  packages = []
  hasrpm = env.WhereIs('rpmbuild')
  ilist = []
  if hasrpm:
    packages.extend(['rpm'])
    ilist.append(env.InstallAs('/usr/sbin/cloudkick-agent', agent[0][0]))
    init = env.Command('packaging/cloudkick-agent', [rh_init], [
                  Copy(pjoin("packaging", shortname), rh_init[0]),
                  Chmod(pjoin("packaging", shortname), 0755)
           ])
    lr = env.Command('packaging/lr/cloudkick-agent', [deb_logrotate], [
                  Copy(pjoin("packaging/lr/", shortname), deb_logrotate[0]),
        ])
    ilist.append(env.Install('/etc/init.d/', init[0]))
    ilist.append(env.Install(pjoin("/usr", "share", "man", "man8"), mangz[0]))
    ilist.append(env.Install('/etc/logrotate.d', lr[0]))

  debname = pkgbase + "_" + env['debian_arch'] +".deb"
  packaging = {'NAME': env['branding_name'],
                'VERSION': env['version_string'],
                'PACKAGEVERSION':  0,
                'LICENSE': 'Proprietary',
                'SUMMARY': env['branding_short'],
                'DESCRIPTION': env['branding_long'],
                'X_RPM_GROUP': 'System/Monitoring',
                'X_RPM_POSTINSTALL': """
CONF="/etc/cloudkick.conf"
CKCONF="/usr/bin/cloudkick-config"
if [ ! -f ${CONF} ]; then
  echo "Please create ${CONF} by running ${CKCONF}"
fi
""",
                'X_RPM_PREUNINSTALL': """
/etc/init.d/cloudkick-agent stop
""",
                'X_RPM_REQUIRES': "cloudkick-config",
                'source': []}
  for p in packages:
    packaging['PACKAGETYPE'] = p
    target_packages.append(env.Package(**packaging))


if env.get('HAVE_DPKG'):
  fr = ""
  if env.WhereIs('fakeroot'):
    fr = env.WhereIs('fakeroot')
  debroot = "debian_temproot"
  deb = env.Command(debname, [abin, deb_control, deb_conffiles, mangz, deb_init, deb_postinst, deb_logrotate, deb_prerm],
                [
                  Delete(debroot),
                  Mkdir(debroot),
                  Mkdir(pjoin(debroot, "DEBIAN")),
                  Copy(pjoin(debroot, 'DEBIAN', 'control'), deb_control[0]),
                  Copy(pjoin(debroot, 'DEBIAN', 'conffiles'), deb_conffiles[0]),
                  Copy(pjoin(debroot, 'DEBIAN', 'postinst'), deb_postinst[0]),
                  Chmod(pjoin(debroot, 'DEBIAN', 'postinst'), 0755),
                  Copy(pjoin(debroot, 'DEBIAN', 'prerm'), deb_prerm[0]),
                  Chmod(pjoin(debroot, 'DEBIAN', 'prerm'), 0755),
                  Mkdir(pjoin(debroot, "usr", "sbin")),
                  Mkdir(pjoin(debroot, "usr", "share", "man", "man8")),
                  Mkdir(pjoin(debroot, "etc")),
                  Mkdir(pjoin(debroot, "etc", "init.d")),
                  Mkdir(pjoin(debroot, "etc", "logrotate.d")),
                  Copy(pjoin(debroot, "usr", "sbin", shortname), abin),
                  Copy(pjoin(debroot, "etc", "init.d", shortname), deb_init[0]),
                  Chmod(pjoin(debroot, "etc", "init.d", shortname), 0755),
                  Copy(pjoin(debroot, "etc", "logrotate.d", shortname), deb_logrotate[0]),
                  Copy(pjoin(debroot, "usr", "share", "man", "man8"), mangz[0]),
                  fr +" dpkg-deb -b "+debroot+" $TARGET",
                  Delete(debroot),
                ])

  target_packages.append(deb)

# Build a tarball with the binary and manpage for Gentoo
if env.get('HAVE_EMERGE'):
  tgzroot = 'tgz_temproot'
  tgzname = pkgbase +"_"+ env['gentoo_arch'] +".tar.gz"
  tgz = env.Tar(tgzname, [abin, mangz])
  target_packages.append(tgz)

if conf.env['PLATFORM'] == 'darwin':
  tgzroot = 'tgz_temproot'
  tgzname = pkgbase +"_darwin.tar.gz"
  tgz = env.Tar(tgzname, [abin, mangz])
  target_packages.append(tgz)

#targets.extend(target_packages)

if env.get('HAVE_WIX'):
  msiname = pkgbase + ".msi"
  wixobjname = pkgbase + ".wixobj"
  wixtmpl = env.SubstFile('packaging/CloudkickAgentInstaller.wxs.in', SUBST_DICT = subst)
  wixobj = env.Command(wixobjname, wixtmpl,
    ['candle.exe $SOURCES -ext WixUtilExtension -out $TARGET'],
    )
  env.Depends(wixobj, [abin])
  msi = env.Command(msiname, wixobj,
    ['light.exe $SOURCES -ext WixUtilExtension -out $TARGET'])
  target_packages.append(msi)

copies = []
for x in target_packages:
  for i in x:
    if hasattr(i, 'rfile'):
      copies.append(env.Command(pjoin('distfiles', os.path.basename(i.get_abspath())), i,
              [Copy('$TARGET', '$SOURCE')]))
target_packages.append(copies)

def gen_deploy(env):
  if not env.get('s3_bucket'):
    print "s3_bucket must be configured to do deployment"
    return []
  s3cmd = "s3cmd"
  if env["PLATFORM"] == "win32":
    s3cmd = "python C:\Python26\Scripts\s3cmd  --no-progress"
  env['s3root'] = env['s3_bucket'] + '/' + env['EQUUS_PLATFORM']
  r = []
  lua = env.Glob("src/lua/remote/*.lua")
  jar = env.Glob("src/lua/remote/*.jar")
  lua.extend(jar)
  lua.extend(env.Glob("src/lua/remote/*.sig"))
  for l in lua:
    short = os.path.basename(l.get_abspath())
    lpath = pjoin("s3_deploy", short)
    t = env.Command(lpath, [l],
        [
          s3cmd+" put --acl-public "+l.get_abspath()+" $s3root/"+ short,
          Copy(lpath, l)
        ])

#    decision = raw_input('Deploy %s to %s? [Y/N] ' % (l, env['s3root'] + '/' + short))
#    if decision.lower() == 'y':
    r.append(t)
  return r

def diff_deployed(env):
  if 'diff' not in COMMAND_LINE_TARGETS:
      return
  lua = env.Glob("src/lua/remote/*.lua")
  for l in lua:
    short = os.path.basename(l.get_abspath())

    current_code_url = env['bootstrap_url'] + env['EQUUS_PLATFORM'] + '/' + short
#    current_code_url = 'http://agent-resources.cloudkick.com/' + env['EQUUS_PLATFORM'] + '/' + short
    print 'curl', '-s', '-o', '/tmp/' + short, current_code_url
    curl = subprocess.call(['curl', '-s', '-o', '/tmp/' + short, current_code_url])
    print 'diff', '-u', '/tmp/' + short, l.get_abspath()
    diff = subprocess.call(['diff', '-u', '/tmp/' + short, l.get_abspath()])


env.Alias('s3deploy', gen_deploy(env))
env.Alias('dist', target_packages)
env.Alias('diff', diff_deployed(env))
env.Default(targets)
