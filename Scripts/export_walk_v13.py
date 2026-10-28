"""Export the longer-stride native-art review at 60fps."""
import export_walk_v11 as exporter
import painted_walk_v13 as rig

exporter.rig = rig
exporter.OUT = rig.OUT
exporter.VERSION = 'v13'

if __name__ == '__main__':
    exporter.main()
