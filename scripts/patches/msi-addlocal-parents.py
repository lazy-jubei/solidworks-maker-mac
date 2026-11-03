#!/usr/bin/env python3
"""Make Wine 11.16's msi.dll install a feature's parents when ADDLOCAL selects a child.

Windows Installer does this. Wine doesn't, so SOLIDWORKS.msi, whose ADDLOCAL names only
features under AddIns <- SolidWorks, "succeeds" with no program files. See WineHQ bug 52876.

Usage: msi-addlocal-parents.py <wine source dir>
"""
import pathlib
import sys

path = pathlib.Path(sys.argv[1]) / "dlls" / "msi" / "action.c"
code = path.read_text()


def replace(text, old, new):
    if text.count(old) != 1:
        sys.exit(f"expected exactly one match for: {old[:60]!r}")
    return text.replace(old, new)


code = replace(code, """static BOOL process_state_property(MSIPACKAGE* package, int level,""",
"""static void request_parent_features(MSIPACKAGE *package, MSIFEATURE *feature, INSTALLSTATE state)
{
    MSIFEATURE *parent;

    if (state != INSTALLSTATE_LOCAL && state != INSTALLSTATE_SOURCE)
        return;
    while (feature->Feature_Parent && (parent = msi_get_loaded_feature( package, feature->Feature_Parent )))
    {
        if (parent->ActionRequest == INSTALLSTATE_UNKNOWN)
        {
            TRACE("requesting parent feature %s\\n", debugstr_w(parent->Feature));
            parent->Action = state;
            parent->ActionRequest = state;
        }
        feature = parent;
    }
}

static BOOL process_state_property(MSIPACKAGE* package, int level,""")
code = replace(code, """                    feature->Action = state;
                    feature->ActionRequest = state;
                    break;
""", """                    feature->Action = state;
                    feature->ActionRequest = state;
                    request_parent_features( package, feature, state );
                    break;
""")
# A required child (UIDisallowAbsent) follows a parent that's being installed. Otherwise
# i386_SWFiles and similar features stay unselected and their files are skipped.
code = replace(code, """static void follow_parent( MSIFEATURE *feature )
{
    FeatureList *fl;
""", """static void follow_parent( MSIFEATURE *feature, int level )
{
    FeatureList *fl;
""")
code = replace(code, """        if (fl->feature->Attributes & msidbFeatureAttributesFollowParent)
        {""", """        if ((fl->feature->Attributes & msidbFeatureAttributesFollowParent) ||
            ((fl->feature->Attributes & msidbFeatureAttributesUIDisallowAbsent) &&
             is_feature_selected( fl->feature, level ) &&
             fl->feature->ActionRequest == INSTALLSTATE_UNKNOWN &&
             (feature->ActionRequest == INSTALLSTATE_LOCAL || feature->ActionRequest == INSTALLSTATE_SOURCE)))
        {""")
code = replace(code, """        follow_parent( fl->feature );
""", """        follow_parent( fl->feature, level );
""")
code = replace(code, """        follow_parent( feature );
""", """        follow_parent( feature, level );
""")
path.write_text(code)
print("patched", path)
