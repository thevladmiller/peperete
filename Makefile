.PHONY: build test app project
build:
	swift build -c release --product peperete
test:
	swift test
	python3 -m unittest discover -s Tests -p 'test_*.py'
project:
	python3 scripts/generate-project.py
app: project
	xcodebuild -project Peperete.xcodeproj -scheme Peperete -configuration Release -derivedDataPath build build
