# Makefile — lệnh tắt cho việc build IPA không cần Apple ID
# (chỉ dùng trên macOS có Xcode + xcodegen)

SHELL := /bin/bash
SCHEME ?= VietMap
OUTPUT ?= dist

.PHONY: help setup project open ipa ipa-verbose device clean distclean lint test

help: ## Hiện danh sách lệnh
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

setup: ## Cài đặt môi trường macOS (Xcode check + xcodegen)
	./scripts/setup-macos.sh

project: ## Sinh VietMap.xcodeproj từ project.yml
	xcodegen generate

open: project ## Mở project trong Xcode (không cần đăng nhập Apple ID)
	open $(SCHEME).xcodeproj

ipa: project ## Build IPA unsigned vào thư mục dist/
	./scripts/make-ipa.sh --scheme $(SCHEME) --output $(OUTPUT)

ipa-verbose: project ## Build IPA kèm full log xcodebuild
	./scripts/make-ipa.sh --scheme $(SCHEME) --output $(OUTPUT) --verbose

device: project ## Build & chạy trên máy thật (CẦN Apple ID miễn phí trong Xcode)
	xcodebuild -project $(SCHEME).xcodeproj -scheme $(SCHEME) \
		-configuration Debug -destination 'generic/platform=iOS' build

clean: ## Xoá build/
	rm -rf build

distclean: clean ## Xoá build/ + dist/ + project đã sinh
	rm -rf $(OUTPUT) $(SCHEME).xcodeproj

lint: ## Kiểm tra cú pháp shell script + cấu hình
	./scripts/selfcheck.sh

test: ## Test khâu đóng gói IPA (chạy được trên Linux/macOS, không cần Xcode)
	./scripts/test-pack.sh
