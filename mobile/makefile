.PHONY: build watch create_app_icon create_splash build_release_android

build:
	fvm dart run build_runner build --delete-conflicting-outputs

watch:
	fvm dart run build_runner watch --delete-conflicting-outputs

create_app_icon:
	fvm flutter pub run flutter_launcher_icons:main

create_splash:
	fvm flutter pub run flutter_native_splash:create

build_release_android:
	fvm flutter build appbundle

migrations:
	fvm dart run drift_dev make-migrations

translation:
	fvm dart run easy_localization:generate -S ../i18n 