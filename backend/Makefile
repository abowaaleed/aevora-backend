.PHONY: test lint format check help

help:
	@echo "Available commands:"
	@echo "  make test    - Run all tests with coverage"
	@echo "  make lint    - Run flake8 linting"
	@echo "  make format  - Format code with black"
	@echo "  make check   - Run lint and format check"
	@echo "  make install - Install dependencies"

test:
	pytest --cov=app --cov-report=term-missing --cov-report=html --cov-fail-under=90

lint:
	flake8 app/ tests/ --max-line-length=100 --ignore=E501,W503

format:
	black app/ tests/

check:
	black --check app/ tests/
	flake8 app/ tests/ --max-line-length=100 --ignore=E501,W503

install:
	pip install -r requirements.txt
	pip install pytest pytest-cov pytest-asyncio black flake8
