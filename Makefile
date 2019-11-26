all: build

build:
	@docker build --tag=aieyes/locserver .
