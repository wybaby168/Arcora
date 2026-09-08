.PHONY: bootstrap build test check app dmg clean
bootstrap:
	./Scripts/bootstrap-engines.sh
build:
	swift build
test: build
	swift test
check:
	python3 Scripts/check-localization.py
	for file in Scripts/*.sh; do bash -n "$$file"; done
app:
	./Scripts/build-app.sh
dmg: app
	./Scripts/make-dmg.sh
clean:
	swift package clean
