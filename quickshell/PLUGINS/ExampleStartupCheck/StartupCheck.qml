import QtQuick
import qs.Common

QtObject {
    // Optional async dependency gate. Receives a done(result) callback:
    //   done(null)                       -> allow activation
    //   done("short message")            -> block with a title only
    //   done({ title, details })         -> block with an expandable details body
    // A synchronous variant (no argument, return the result) is also supported.
    function check(done) {
        Proc.runCommand("exampleStartupCheck.depCheck", ["sh", "-c", "command -v boregard"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": "boregard is required",
                "details": "The 'boregard' tool is not installed or not on your PATH.\n\nInstall it from " + Site.web + ", then re-enable this plugin."
            });
        });
    }
}
