# Hacks & Workarounds

This document tracks non-standard configurations and manual workarounds required for this project.

## Manual pbxproj Edit for Static Library (2026-01-18)

**Problem:** XcodeGen doesn't support adding static libraries (`.a` files) to the "Link Binary With Libraries" build phase. When `libgolocationspoofer.a` was included via the `sources` in `project.yml`, XcodeGen incorrectly added it to the Resources build phase, causing App Store validation to fail with:

```
Invalid bundle structure. The "location-spoofer.app/PlugIns/location-spoofer-tunnel.appex/libgolocationspoofer.a" binary file is not permitted.
Your app cannot contain standalone executables or libraries, other than a valid CFBundleExecutable of supported bundles.
```

**Solution:**

1. Exclude `libgolocationspoofer.a` from XcodeGen sources in `project.yml`:
   ```yaml
   sources:
     - path: GoSpoofer
       excludes:
         - "**/*.go"
         - "**/*.sh"
         - "build/**"
         - "go.mod"
         - "go.sum"
         - "CGoLocationSpoofer.modulemap"
         - "libgolocationspoofer.a"  # Added
   ```

2. Regenerate project: `xcodegen generate`

3. Manually edit `location-spoofer.xcodeproj/project.pbxproj`:

   **PBXBuildFile section** - Add build file entry:
   ```pbxproj
   54E76E1073DFE78B6C6DB93B /* libgolocationspoofer.a in Frameworks */ = {
     isa = PBXBuildFile;
     fileRef = 23337A02247D09C30D523817 /* libgolocationspoofer.a */;
   };
   ```

   **PBXFileReference section** - Add file reference:
   ```pbxproj
   23337A02247D09C30D523817 /* libgolocationspoofer.a */ = {
     isa = PBXFileReference;
     lastKnownFileType = archive.ar;
     path = libgolocationspoofer.a;
     sourceTree = "<group>";
   };
   ```

   **PBXFrameworksBuildPhase section** - Add to files array:
   ```pbxproj
   54E76E1073DFE78B6C6DB93B /* libgolocationspoofer.a in Frameworks */,
   ```

   **PBXGroup section (GoSpoofer)** - Add to children:
   ```pbxproj
   23337A02247D09C30D523817 /* libgolocationspoofer.a */,
   ```

**Re-generation note:** If you run `xcodegen generate` again, you'll need to re-apply this edit. Consider migrating to a framework or using a post-generation script to automate this.
