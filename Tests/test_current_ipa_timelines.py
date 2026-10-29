"""Reject truncated indexed dances in the release-package validator."""
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('ipa', Path(__file__).resolve().parents[1] / 'Scripts/verify_ipa.py')
ipa = importlib.util.module_from_spec(spec); spec.loader.exec_module(ipa)

class Archive:
    def __init__(self, data): self.data = data
    def read(self, name): return json.dumps(self.data).encode()

class CurrentTimelineTests(unittest.TestCase):
    def fixture(self):
        table = [{'action':'idle'}]
        table += [{'action':a,'sourceFrame':f} for a in ('dance1','dance2') for f in (0,719)]
        plans=[]
        for bank in range(128):
            indices=[]
            for action, bit, first in (('dance1',16,1),('dance2',32,3)):
                if bank//2 & bit: indices += [first]*389+[first+1]
            indices += [0]*(3600-len(indices))
            plans.append({'id':bank,'mask':bank//2,'frames':[],'frameIndices':indices})
        return dict(fps=30,period=120,scenes=['black','meadow','night'],stagePixels=[180,96],travelPixels=100,plans=plans,frameTable=table)
    def verify(self, data):
        ipa.verify_current_timelines(Archive(data),'App',[{'id':'dafeiyu','motion':{'timelineResource':'MotionTimelineDafeiyu','dailyActions':[{'id':'dance1'},{'id':'dance2'}]}}])
    def test_complete_two_minute_plans_pass(self): self.verify(self.fixture())
    def test_missing_bank_fails(self):
        data=self.fixture();data['plans'].pop()
        with self.assertRaises(ValueError):self.verify(data)
    def test_invalid_index_fails(self):
        data=self.fixture();data['plans'][0]['frameIndices'][0]=999
        with self.assertRaises(ValueError):self.verify(data)
    def test_dance_missing_last_source_pose_fails(self):
        data=self.fixture();data['frameTable'][2]['sourceFrame']=718
        with self.assertRaisesRegex(ValueError,'shortened'):self.verify(data)
    def test_truncated_dance_fails(self):
        data=self.fixture();data['plans'][32]['frameIndices']=[1,2]+[0]*3598
        with self.assertRaisesRegex(ValueError,'shortened'):self.verify(data)
