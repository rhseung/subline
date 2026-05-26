.PHONY: install build clean

install: build
	pkill -x Subline || true
	rm -rf /Applications/Subline.app
	cp -Rf .xcode-derived/Build/Debug/Subline.app /Applications/Subline.app
	open /Applications/Subline.app

build:
	touch Sources/Subline/*.swift
	xcodebuild -project Subline.xcodeproj \
		-scheme Subline \
		-configuration Debug \
		SYMROOT=.xcode-derived/Build \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

clean:
	rm -rf .xcode-derived/ .build/
