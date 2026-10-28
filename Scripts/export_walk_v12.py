"""Latest native-art full RGBA frame and preview exporter."""
import export_walk_v11 as exporter
import painted_walk_v12 as rig
exporter.rig=rig
exporter.OUT=rig.OUT
exporter.VERSION='v12'

if __name__=='__main__':exporter.main()
