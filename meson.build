project('singularity-nearby-app', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-nearby-app"', language: 'c')
subdir('po')

gtk_dep = dependency('gtk4', version: '>= 4.16')
gee_dep = dependency('gee-0.8')
gio_dep = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

model_sources = files(
  'src/format.vala',
  'src/transfer_store.vala',
)

executable('singularity-nearby-app',
  model_sources + files(
    'src/drop_zone.vala',
    'src/pairing_view.vala',
    'src/device_view.vala',
    'src/messages_view.vala',
    'src/notifications_view.vala',
    'src/received_view.vala',
    'src/send_dialogs.vala',
    'src/window.vala',
    'src/search.vala',
    'src/app.vala',
  ),
  dependencies: [gtk_dep, gee_dep, gio_dep, gio_unix_dep, libsingularity_dep],
  install: true
)

install_data('data/dev.sinty.Nearby.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/dev.sinty.Nearby.search-provider.ini',
  rename: 'dev.sinty.Nearby.ini',
  install_dir: get_option('datadir') / 'singularity' / 'search-providers'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.Nearby.App.service.in',
  output: 'dev.sinty.Nearby.App.service',
  configuration: service_conf,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

format_test = executable('nearby-app-format-test',
  model_sources + files('tests/format_test.vala'),
  dependencies: [gtk_dep, gee_dep, gio_dep, libsingularity_dep],
)
test('nearby-app-format', format_test, env: ['LC_ALL=C'])
