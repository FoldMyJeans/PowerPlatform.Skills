"""Restore search on Classic ComboBox people pickers inside a Studio-published .msapp.

An app shipped from pa.yaml source loses every combo's SearchItems (the YAML cannot carry it).
Once Studio has opened and published the app, each combo holds the template sample
`Search(ComboBoxSample, Self.SearchText, Value1)`: typing a name finds nobody and saved people
only show after the list is opened. This rewrites SearchItems from the combo's own Items formula,
`Choices(List.Column)` -> `Choices(List.Column,<combo>.SearchText)`. SearchFields is left alone.

  python fix_picker_search.py app.msapp               report only, exit 1 if anything needs fixing
  python fix_picker_search.py app.msapp fixed.msapp   write the fixed copy
  python fix_picker_search.py --selftest
"""
import io
import json
import re
import sys
import zipfile

CHOICES = re.compile(r'^\s*Choices\(\s*(.+?)\s*\)\s*$', re.S)


def walk(c):
    yield c
    for ch in c.get('Children', []):
        yield from walk(ch)


def fix_control(c):
    """Return the (property, old, new) changes applied to this control, or a reason string."""
    if not c.get('Template', {}).get('Id', '').endswith('/combobox'):
        return []
    rules = {r['Property']: r for r in c.get('Rules', [])}
    m = CHOICES.match(rules.get('Items', {}).get('InvariantScript', ''))
    if not m:
        return f"{c['Name']}: Items is not Choices(List.Column), fix SearchItems by hand"
    changes = []
    want = f"Choices({m.group(1)},{c['Name']}.SearchText)"
    si = rules.get('SearchItems')
    if si is None:
        return f"{c['Name']}: no SearchItems rule, the app was not published from Studio"
    if si['InvariantScript'] != want:
        changes.append(('SearchItems', si['InvariantScript'], want))
        si['InvariantScript'] = want
    return changes


def run(src, dst=None, out=print):
    zin = zipfile.ZipFile(src)
    if 'packed.json' in zin.namelist():
        out('This msapp still loads from YAML source. Open the app in Studio, Publish, download again.')
        return 2
    patched, todo, manual = {}, 0, []
    for name in zin.namelist():
        if not (name.startswith('Controls/') and name.endswith('.json')):
            continue
        doc = json.loads(zin.read(name).decode('utf-8-sig'))
        touched = False
        for c in walk(doc['TopParent']):
            res = fix_control(c)
            if isinstance(res, str):
                manual.append(res)
                continue
            for prop, old, new in res:
                out(f"{c['Name']}.{prop}: {old}  ->  {new}")
                todo += 1
                touched = True
        if touched:
            patched[name] = json.dumps(doc, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
    for m in manual:
        out('MANUAL ' + m)
    out(f'{todo} change(s), {len(manual)} manual')
    if dst:
        with zipfile.ZipFile(dst, 'w') as zout:
            for info in zin.infolist():
                zout.writestr(info, patched.get(info.filename, zin.read(info.filename)))
        out(f'wrote {dst}')
        return 1 if manual else 0
    return 1 if todo or manual else 0


def selftest():
    def combo(name, items, search):
        return {'Name': name, 'Template': {'Id': 'http://microsoft.com/appmagic/combobox'}, 'Rules': [
            {'Property': 'Items', 'InvariantScript': items},
            {'Property': 'SearchItems', 'InvariantScript': search},
            {'Property': 'SearchFields', 'InvariantScript': '["Claims"]'}]}
    screen = {'TopParent': {'Name': 'scr', 'Template': {'Id': 'screen'}, 'Children': [
        combo('cmb_Owner', 'Choices(Deals.Sales_Owner)', 'Search(ComboBoxSample, Self.SearchText, Value1)'),
        combo('cmb_Done', 'Choices(Deals.Lead)', 'Choices(Deals.Lead,cmb_Done.SearchText)'),
        combo('cmb_Odd', 'colPeople', 'Search(ComboBoxSample, Self.SearchText, Value1)')]}}
    src, dst, log = io.BytesIO(), io.BytesIO(), []
    with zipfile.ZipFile(src, 'w') as z:
        z.writestr('Controls/1.json', json.dumps(screen))
        z.writestr('Header.json', '{}')
    assert run(src, out=log.append) == 1
    assert run(src, dst, out=log.append) == 1  # cmb_Odd still needs a human
    fixed = {c['Name']: {r['Property']: r['InvariantScript'] for r in c['Rules']}
             for c in walk(json.loads(zipfile.ZipFile(dst).read('Controls/1.json'))['TopParent']) if 'Rules' in c}
    assert fixed['cmb_Owner']['SearchItems'] == 'Choices(Deals.Sales_Owner,cmb_Owner.SearchText)'
    assert fixed['cmb_Owner']['SearchFields'] == '["Claims"]'  # never touched
    assert fixed['cmb_Odd']['SearchItems'].startswith('Search(ComboBoxSample')  # left for a human
    assert any('MANUAL cmb_Odd' in line for line in log)
    assert zipfile.ZipFile(dst).read('Header.json') == b'{}'
    packed = io.BytesIO()
    with zipfile.ZipFile(packed, 'w') as z:
        z.writestr('packed.json', '{}')
    assert run(packed, out=log.append) == 2
    print('selftest ok')


if __name__ == '__main__':
    if sys.argv[1:] == ['--selftest']:
        selftest()
    elif len(sys.argv) in (2, 3):
        sys.exit(run(*sys.argv[1:]))
    else:
        sys.exit(__doc__)
