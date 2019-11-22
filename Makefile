all: build

build:
	@docker build --tag=omofresh/bindftp .
