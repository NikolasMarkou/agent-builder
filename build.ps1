# build.ps1 - PowerShell build script for Agent Builder Claude Skill
# Usage: .\build.ps1 [command]
# Commands: build, build-combined, package, package-combined, package-tar, validate, clean, list, help

param(
    [Parameter(Position=0)]
    [string]$Command = "package"
)

$SkillName = "agent-builder"
$Version = (Get-Content "$PSScriptRoot/VERSION" -Raw).Trim()
$BuildDir = "build"
$DistDir = "dist"

function Show-Help {
    Write-Host "Agent Builder Skill - Build Script" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Usage: .\build.ps1 [command]"
    Write-Host ""
    Write-Host "Commands:"
    Write-Host "  build            - Build skill package structure"
    Write-Host "  build-combined   - Build single-file skill with inlined references"
    Write-Host "  package          - Create zip package"
    Write-Host "  package-combined - Create single-file skill in dist/"
    Write-Host "  package-tar      - Create tarball package"
    Write-Host "  validate         - Validate skill structure"
    Write-Host "  clean            - Remove build artifacts"
    Write-Host "  list             - Show package contents"
    Write-Host "  help             - Show this help"
    Write-Host ""
    Write-Host "Skill: $SkillName v$Version" -ForegroundColor Green
}

function Invoke-Build {
    Write-Host "Building skill package: $SkillName" -ForegroundColor Yellow

    # Create directories
    $skillDir = Join-Path $BuildDir $SkillName
    New-Item -ItemType Directory -Force -Path $skillDir | Out-Null
    New-Item -ItemType Directory -Force -Path "$skillDir/references" | Out-Null

    # Copy main skill file
    Copy-Item "src/SKILL.md" $skillDir

    # Copy reference files
    Copy-Item "src/references/*.md" "$skillDir/references/"

    # Copy documentation
    @("README.md", "LICENSE", "CHANGELOG.md") | ForEach-Object {
        if (Test-Path $_) {
            Copy-Item $_ $skillDir
        }
    }

    Write-Host "Build complete: $skillDir" -ForegroundColor Green
}

function Invoke-BuildCombined {
    Write-Host "Building combined single-file skill..." -ForegroundColor Yellow

    New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

    $outputFile = Join-Path $BuildDir "$SkillName-combined.md"

    # Start with SKILL.md
    $content = Get-Content "src/SKILL.md" -Raw
    $content += "`n`n---`n`n# Bundled References`n"

    # Append each reference file
    Get-ChildItem "src/references/*.md" | Sort-Object Name | ForEach-Object {
        $content += "`n---`n`n"
        $content += Get-Content $_.FullName -Raw
    }

    Set-Content -Path $outputFile -Value $content

    Write-Host "Combined skill created: $outputFile" -ForegroundColor Green
}

function Invoke-Package {
    Invoke-Build

    Write-Host "Packaging skill as zip..." -ForegroundColor Yellow

    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

    $zipFile = Join-Path (Resolve-Path $DistDir) "$SkillName-v$Version.zip"
    $sourcePath = Resolve-Path (Join-Path $BuildDir $SkillName)

    # Remove existing zip if present
    if (Test-Path $zipFile) {
        Remove-Item $zipFile
    }

    # Use .NET ZipFile for cross-platform compatibility
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::Open($zipFile, 'Create')

    try {
        Get-ChildItem -Path $sourcePath -Recurse -File | ForEach-Object {
            $relativePath = $_.FullName.Substring($sourcePath.Path.Length + 1)
            # Convert backslashes to forward slashes for cross-platform compatibility
            $entryName = "$SkillName/" + ($relativePath -replace '\\', '/')
            [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $_.FullName, $entryName) | Out-Null
        }
    }
    finally {
        $zip.Dispose()
    }

    Write-Host "Package created: $zipFile" -ForegroundColor Green
}

function Invoke-PackageCombined {
    Invoke-BuildCombined

    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

    $source = Join-Path $BuildDir "$SkillName-combined.md"
    $dest = Join-Path $DistDir "$SkillName-combined.md"

    Copy-Item $source $dest

    Write-Host "Combined skill copied to: $dest" -ForegroundColor Green
}

function Invoke-Validate {
    Write-Host "Validating skill structure..." -ForegroundColor Yellow

    $errors = @()

    # Check SKILL.md exists
    if (-not (Test-Path "src/SKILL.md")) {
        $errors += "ERROR: src/SKILL.md not found"
    } else {
        $content = Get-Content "src/SKILL.md" -Raw
        if ($content -notmatch "(?m)^name:") {
            $errors += "ERROR: SKILL.md missing 'name' in frontmatter"
        }
        if ($content -notmatch "(?m)^description:") {
            $errors += "ERROR: SKILL.md missing 'description' in frontmatter"
        }

        # Verify SKILL.md starts with frontmatter
        if ($content -notmatch "^---") {
            $errors += "ERROR: SKILL.md missing frontmatter opening ---"
        }
        # Verify SKILL.md has closing frontmatter delimiter
        $lines = (Get-Content "src/SKILL.md")
        $closingFound = $false
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^---") { $closingFound = $true; break }
        }
        if (-not $closingFound) {
            $errors += "ERROR: SKILL.md missing frontmatter closing ---"
        }

        # Verify all references/ cross-references resolve to actual files
        Write-Host "Checking cross-references..."
        $refs = [regex]::Matches($content, 'references/[A-Za-z0-9_-]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique
        foreach ($ref in $refs) {
            if (-not (Test-Path "src/$ref")) {
                $errors += "ERROR: SKILL.md references src/$ref but file not found"
            }
        }
    }

    # Check directories
    if (-not (Test-Path "src/references")) {
        $errors += "ERROR: src/references/ directory not found"
    }

    # Verify README.md lists all reference files
    Write-Host "Checking README.md lists all reference files..."
    if (Test-Path "src/references") {
        $readmeContent = Get-Content "README.md" -Raw -ErrorAction SilentlyContinue
        if ($readmeContent) {
            Get-ChildItem "src/references/*.md" | ForEach-Object {
                if ($readmeContent -notmatch [regex]::Escape($_.Name)) {
                    $errors += "ERROR: README.md project structure missing $($_.Name)"
                }
            }
        }
    }

    # Verify CLAUDE.md lists all reference files
    Write-Host "Checking CLAUDE.md lists all reference files..."
    if (Test-Path "src/references") {
        $claudeContent = Get-Content "CLAUDE.md" -Raw -ErrorAction SilentlyContinue
        if ($claudeContent) {
            Get-ChildItem "src/references/*.md" | ForEach-Object {
                if ($claudeContent -notmatch [regex]::Escape($_.Name)) {
                    $errors += "ERROR: CLAUDE.md repository structure missing $($_.Name)"
                }
            }
        }
    }

    # Verify README.md version badge matches VERSION file
    Write-Host "Checking README.md version badge..."
    if (Test-Path "README.md") {
        $readmeContent = Get-Content "README.md" -Raw
        if ($readmeContent -notmatch "Skill-v$([regex]::Escape($Version))") {
            $errors += "ERROR: README.md version badge does not match VERSION ($Version)"
        }
    }

    # Verify no deprecated model strings remain (code and prose)
    Write-Host "Checking model string consistency..."
    $deprecatedHits = Select-String -Path "src/references/*.md", "src/SKILL.md" -Pattern 'gpt-4\.1[^+]|gpt-4\.1$|Claude-v1' -ErrorAction SilentlyContinue
    if ($deprecatedHits) {
        foreach ($hit in $deprecatedHits) {
            $errors += "ERROR: Deprecated model string in $($hit.Filename):$($hit.LineNumber): $($hit.Line.Trim())"
        }
    }

    # Verify every reference file has at least one code example
    Write-Host "Checking code example presence..."
    Get-ChildItem "src/references/*.md" | ForEach-Object {
        $refContent = Get-Content $_.FullName -Raw
        if ($refContent -notmatch '```') {
            $errors += "ERROR: $($_.Name) has no code examples"
        }
    }

    # Verify content guideline compliance (failure modes or when-not-to-use section heading)
    Write-Host "Checking content guideline compliance..."
    Get-ChildItem "src/references/*.md" | ForEach-Object {
        $refContent = Get-Content $_.FullName -Raw
        if ($refContent -notmatch '(?mi)^##+ *(\d+\. *)?.*(Failure Mode|Anti-Pattern|When NOT|When .* Not)') {
            $errors += "ERROR: $($_.Name) missing 'When NOT to use' or Failure Modes section heading"
        }
    }

    # Verify failure modes heading exists in files that need them (framework and data references)
    Write-Host "Checking failure modes sections..."
    $mustHaveFailureModes = @(
        "langchain-langgraph.md", "strands.md", "dspy.md",
        "retrieval.md", "text-tools.md", "entity-resolution.md",
        "tabular-data.md", "structured-classification.md",
        "embeddings.md"
    )
    foreach ($name in $mustHaveFailureModes) {
        $refPath = "src/references/$name"
        if (Test-Path $refPath) {
            $refContent = Get-Content $refPath -Raw
            if ($refContent -notmatch '(?mi)^##+ *(\d+\. *)?(Failure Mode|Anti-Pattern)') {
                $errors += "ERROR: $name missing Failure Modes or Anti-Patterns section heading"
            }
        }
    }

    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }

    Invoke-ValidateXrefStyle
    Invoke-ValidateFrameworkParity
    Invoke-ValidateBenchmarkStamps
    Invoke-ValidateCitationDensity

    Write-Host "Validation passed!" -ForegroundColor Green
}

function Invoke-ValidateXrefStyle {
    Write-Host "Checking cross-reference style inside references/..." -ForegroundColor Yellow
    $hits = @()
    Get-ChildItem -Path "src/references" -Filter "*.md" | ForEach-Object {
        $lines = Get-Content $_.FullName
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '\breferences/[a-z][a-z_-]*\.md\b') {
                $hits += ("{0}:{1}: {2}" -f $_.FullName, ($i + 1), $lines[$i])
            }
        }
    }
    if ($hits.Count -gt 0) {
        Write-Host "ERROR: rooted 'references/foo.md' paths found inside src/references/ (use bare sibling 'foo.md'):" -ForegroundColor Red
        $hits | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
}

function Invoke-ValidateFrameworkParity {
    Write-Host "Checking framework table parity (SKILL.md <-> frameworks.md)..." -ForegroundColor Yellow
    $skillContent = Get-Content "src/SKILL.md" -Raw
    $step3Match = [regex]::Match($skillContent, '(?s)### Step 3: Select Framework.*?### Step 4:')
    $skillFrameworks = @()
    if ($step3Match.Success) {
        $pattern = 'CrewAI|Strands Agents|OpenAI Agents SDK|Semantic Kernel|Google ADK|Mastra|LlamaIndex|DSPy|Agno|Smolagents'
        $skillFrameworks = [regex]::Matches($step3Match.Value, $pattern) | ForEach-Object { $_.Value } | Sort-Object -Unique
    }
    $refContent = Get-Content "src/references/frameworks.md" -Raw
    $matrixMatch = [regex]::Match($refContent, '(?s)## Framework Selection Matrix.*?## Head-to-Head')
    $refFrameworks = @()
    if ($matrixMatch.Success) {
        $refFrameworks = ([regex]::Matches($matrixMatch.Value, '(?m)^## (.+)$') |
            ForEach-Object { ($_.Groups[1].Value -split ' */ ')[0].Trim() } |
            Where-Object { $_ -notin @('Framework Selection Matrix', 'Head-to-Head') }) |
            Sort-Object -Unique
    }
    $missingInRef   = $skillFrameworks | Where-Object { $refFrameworks -notcontains $_ }
    $missingInSkill = $refFrameworks   | Where-Object { $skillFrameworks -notcontains $_ }
    if ($missingInRef.Count -gt 0) {
        Write-Host "WARN: frameworks in SKILL.md Step 3 not found as '## X' heading in frameworks.md:" -ForegroundColor Yellow
        $missingInRef | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    if ($missingInSkill.Count -gt 0) {
        Write-Host "WARN: frameworks with '## X' heading in frameworks.md not listed in SKILL.md Step 3 override table:" -ForegroundColor Yellow
        $missingInSkill | ForEach-Object { Write-Host $_ -ForegroundColor Yellow }
    }
    Write-Host "Framework parity check complete (advisory)."
}

function Invoke-ValidateBenchmarkStamps {
    Write-Host "Checking benchmark date-stamps..." -ForegroundColor Yellow
    $benchmarkFiles = @(
        "multi-hop-rag.md", "retrieval.md", "entity-resolution.md", "evals.md",
        "llm-as-judge.md", "binary-evals.md", "tabular-data.md", "embeddings.md"
    )
    $errors = @()
    foreach ($name in $benchmarkFiles) {
        $refPath = "src/references/$name"
        if (Test-Path $refPath) {
            $refContent = Get-Content $refPath -Raw
            if ($refContent -notmatch '<!-- *benchmarks-as-of: *\d{4}-\d{2} *-->') {
                $errors += "ERROR: $name missing <!-- benchmarks-as-of: YYYY-MM --> banner"
            }
        }
    }
    if ($errors.Count -gt 0) {
        $errors | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        exit 1
    }
}

function Invoke-ValidateCitationDensity {
    Write-Host "Checking citation density (advisory)..." -ForegroundColor Yellow
    Get-ChildItem -Path "src/references" -Filter "*.md" | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        $nums  = [regex]::Matches($content, '[0-9]+(\.[0-9]+)?%|[0-9]+\.[0-9]+\s*(points?|pp|x|ms|s|F1|BLEU|ROUGE|accuracy)').Count
        $cites = [regex]::Matches($content, 'https?://|et al\.|\([A-Z][a-z]+,? [0-9]{4}\)').Count
        if ($nums -gt 8 -and $cites -lt 2) {
            Write-Host ("WARN: {0} has {1} numeric claims but only {2} citation markers" -f $_.Name, $nums, $cites) -ForegroundColor Yellow
        }
    }
    Write-Host "Citation density check complete (advisory)."
}

function Invoke-PackageTar {
    Invoke-Build

    Write-Host "Packaging skill as tarball..." -ForegroundColor Yellow

    New-Item -ItemType Directory -Force -Path $DistDir | Out-Null

    $tarFile = Join-Path (Resolve-Path $DistDir) "$SkillName-v$Version.tar.gz"
    $sourcePath = Join-Path $BuildDir $SkillName

    if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
        Write-Host "ERROR: tar command not found. Install tar or use 'package' (zip) instead." -ForegroundColor Red
        exit 1
    }

    tar -czvf $tarFile -C $BuildDir $SkillName
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Tarball creation failed!" -ForegroundColor Red
        exit 1
    }

    Write-Host "Package created: $tarFile" -ForegroundColor Green
}

function Invoke-Clean {
    Write-Host "Cleaning build artifacts..." -ForegroundColor Yellow

    if (Test-Path $BuildDir) {
        Remove-Item -Recurse -Force $BuildDir
    }
    if (Test-Path $DistDir) {
        Remove-Item -Recurse -Force $DistDir
    }

    Write-Host "Clean complete" -ForegroundColor Green
}

function Invoke-List {
    Invoke-Build

    Write-Host "Package contents:" -ForegroundColor Cyan
    Get-ChildItem -Recurse (Join-Path $BuildDir $SkillName) |
        Where-Object { -not $_.PSIsContainer } |
        ForEach-Object { $_.FullName.Replace((Get-Location).Path + [IO.Path]::DirectorySeparatorChar, "") }
}

# Execute command
switch ($Command.ToLower()) {
    "build"            { Invoke-Build }
    "build-combined"   { Invoke-BuildCombined }
    "package"          { Invoke-Package }
    "package-combined" { Invoke-PackageCombined }
    "package-tar"      { Invoke-PackageTar }
    "validate"         { Invoke-Validate }
    "clean"            { Invoke-Clean }
    "list"             { Invoke-List }
    "help"             { Show-Help }
    default            {
        Show-Help
        exit 1
    }
}
