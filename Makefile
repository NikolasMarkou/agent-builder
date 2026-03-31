# Makefile for Agent Builder Claude Skill
# Packages the repository into a distributable Claude skill format

SKILL_NAME := agent-builder
VERSION := $(shell cat VERSION)
BUILD_DIR := build
DIST_DIR := dist

# Files to include in the skill package
SKILL_FILE := src/SKILL.md
REFERENCE_FILES := $(sort $(wildcard src/references/*.md))
DOC_FILES := README.md LICENSE CHANGELOG.md

# Default target
.PHONY: all
all: package

# Build the skill package structure
.PHONY: build
build:
	@echo "Building skill package: $(SKILL_NAME)"
	mkdir -p $(BUILD_DIR)/$(SKILL_NAME)
	mkdir -p $(BUILD_DIR)/$(SKILL_NAME)/references
	@# Copy main skill file
	cp $(SKILL_FILE) $(BUILD_DIR)/$(SKILL_NAME)/
	@# Copy reference files
	cp $(REFERENCE_FILES) $(BUILD_DIR)/$(SKILL_NAME)/references/
	@# Copy documentation
	cp $(DOC_FILES) $(BUILD_DIR)/$(SKILL_NAME)/ 2>/dev/null || true
	@echo "Build complete: $(BUILD_DIR)/$(SKILL_NAME)"

# Create a combined single-file skill (SKILL.md with references inlined)
.PHONY: build-combined
build-combined:
	@echo "Building combined single-file skill..."
	mkdir -p $(BUILD_DIR)
	cp $(SKILL_FILE) $(BUILD_DIR)/$(SKILL_NAME)-combined.md
	@echo "" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md
	@echo "---" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md
	@echo "" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md
	@echo "# Bundled References" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md
	@for ref in $(REFERENCE_FILES); do \
		echo "" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md; \
		echo "---" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md; \
		echo "" >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md; \
		cat $$ref >> $(BUILD_DIR)/$(SKILL_NAME)-combined.md; \
	done
	@echo "Combined skill created: $(BUILD_DIR)/$(SKILL_NAME)-combined.md"

# Package as zip for distribution
.PHONY: package
package: build
	@echo "Packaging skill as zip..."
	mkdir -p $(DIST_DIR)
	cd $(BUILD_DIR) && zip -r ../$(DIST_DIR)/$(SKILL_NAME)-v$(VERSION).zip $(SKILL_NAME)
	@echo "Package created: $(DIST_DIR)/$(SKILL_NAME)-v$(VERSION).zip"

# Package combined single-file version
.PHONY: package-combined
package-combined: build-combined
	mkdir -p $(DIST_DIR)
	cp $(BUILD_DIR)/$(SKILL_NAME)-combined.md $(DIST_DIR)/
	@echo "Combined skill copied to: $(DIST_DIR)/$(SKILL_NAME)-combined.md"

# Create tarball
.PHONY: package-tar
package-tar: build
	@echo "Packaging skill as tarball..."
	mkdir -p $(DIST_DIR)
	cd $(BUILD_DIR) && tar -czvf ../$(DIST_DIR)/$(SKILL_NAME)-v$(VERSION).tar.gz $(SKILL_NAME)
	@echo "Package created: $(DIST_DIR)/$(SKILL_NAME)-v$(VERSION).tar.gz"

# Validate skill structure
.PHONY: validate
validate:
	@echo "Validating skill structure..."
	@test -f $(SKILL_FILE) || (echo "ERROR: $(SKILL_FILE) not found" && exit 1)
	@grep -q "^name:" $(SKILL_FILE) || (echo "ERROR: SKILL.md missing 'name' in frontmatter" && exit 1)
	@grep -q "^description:" $(SKILL_FILE) || (echo "ERROR: SKILL.md missing 'description' in frontmatter" && exit 1)
	@test -d src/references || (echo "ERROR: src/references/ directory not found" && exit 1)
	@# Verify all references/ cross-references in SKILL.md resolve to actual files
	@echo "Checking cross-references..."
	@fail=0; for ref in $$(grep -oE 'references/[a-z0-9_-]+\.md' $(SKILL_FILE) | sort -u); do \
		test -f "src/$$ref" || { echo "ERROR: $(SKILL_FILE) references src/$$ref but file not found"; fail=1; }; \
	done; [ $$fail -eq 0 ]
	@# Verify SKILL.md has frontmatter delimiters
	@head -1 $(SKILL_FILE) | grep -q "^---" || (echo "ERROR: SKILL.md missing frontmatter opening ---" && exit 1)
	@awk 'NR>1 && /^---/{found=1; exit} END{if(!found){print "ERROR: SKILL.md missing frontmatter closing ---"; exit 1}}' $(SKILL_FILE)
	@# Verify README.md project structure lists all reference files
	@echo "Checking README.md lists all reference files..."
	@fail=0; for ref in $(notdir $(REFERENCE_FILES)); do \
		grep -q "$$ref" README.md || { echo "ERROR: README.md project structure missing $$ref"; fail=1; }; \
	done; [ $$fail -eq 0 ]
	@# Verify CLAUDE.md repository structure lists all reference files
	@echo "Checking CLAUDE.md lists all reference files..."
	@fail=0; for ref in $(notdir $(REFERENCE_FILES)); do \
		grep -q "$$ref" CLAUDE.md || { echo "ERROR: CLAUDE.md repository structure missing $$ref"; fail=1; }; \
	done; [ $$fail -eq 0 ]
	@# Verify README.md version badge matches VERSION file
	@echo "Checking README.md version badge..."
	@grep -q "Skill-v$(VERSION)" README.md || (echo "ERROR: README.md version badge does not match VERSION ($(VERSION))" && exit 1)
	@# Verify no deprecated model strings remain (code and prose)
	@echo "Checking model string consistency..."
	@if grep -rEin 'gpt-4\.1[^+]|gpt-4\.1$$|Claude-v1' src/; then echo "ERROR: Deprecated model strings found (use gpt-4o/gpt-4o-mini)" && exit 1; fi
	@# Verify every reference file has at least one code example
	@echo "Checking code example presence..."
	@fail=0; for ref in $$(ls src/references/*.md 2>/dev/null); do \
		grep -q '```' $$ref || { echo "ERROR: $$ref has no code examples"; fail=1; }; \
	done; [ $$fail -eq 0 ]
	@# Verify content guideline compliance (failure modes or when-not-to-use)
	@echo "Checking content guideline compliance..."
	@fail=0; for ref in $$(ls src/references/*.md 2>/dev/null); do \
		name=$$(basename $$ref); \
		if ! grep -qi "when not\|failure mode\|anti-pattern\|pitfall" $$ref; then \
			echo "ERROR: $$name missing 'When NOT to use' or failure modes section"; fail=1; \
		fi; \
	done; [ $$fail -eq 0 ]
	@# Verify failure modes heading exists in files that need them (framework and data references)
	@echo "Checking failure modes sections..."
	@fail=0; for ref in src/references/langchain-langgraph.md src/references/strands.md src/references/dspy.md \
		src/references/retrieval.md src/references/text-tools.md src/references/entity-resolution.md \
		src/references/tabular-data.md src/references/structured-classification.md; do \
		name=$$(basename $$ref); \
		if ! grep -qiE '^##+ *([0-9]+\. *)?(Failure Mode|Anti-Pattern)' $$ref; then \
			echo "ERROR: $$name missing Failure Modes or Anti-Patterns section heading"; fail=1; \
		fi; \
	done; [ $$fail -eq 0 ]
	@echo "Validation passed!"

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)
	rm -rf $(DIST_DIR)
	@echo "Clean complete"

# Show package contents
.PHONY: list
list: build
	@echo "Package contents:"
	@find $(BUILD_DIR)/$(SKILL_NAME) -type f | sort

# Help
.PHONY: help
help:
	@echo "Agent Builder Skill - Makefile targets:"
	@echo ""
	@echo "  make build           - Build skill package structure"
	@echo "  make build-combined  - Build single-file skill with inlined references"
	@echo "  make package         - Create zip package (default)"
	@echo "  make package-combined - Create single-file skill package"
	@echo "  make package-tar     - Create tarball package"
	@echo "  make validate        - Validate skill structure"
	@echo "  make clean           - Remove build artifacts"
	@echo "  make list            - Show package contents"
	@echo "  make help            - Show this help"
	@echo ""
	@echo "Skill: $(SKILL_NAME) v$(VERSION)"
