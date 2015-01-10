iOSense
============================

Pebble + iOS sensor logging. Includes pebble accelerometer, phone accelerometer, gyro, magnitometer, location, heading, altitude, and everything else that CoreMotion and CoreLocation give you. Currently just writes to timestamped csvs in the app's documents directory at present, but planning on adding the ability to email data soon.

Also contains a GUI (albeit an ugly one) for attaching an arbitrary set of labels to current readings and starting and stopping data collection. The intent is to allow easy annotation of particular actions or phenomenon. To set what labels are present, just modify the dictionaries in Labels.h.

Another key value add here is that it deals with asynchronous updates to each sensor value and writes out a clean, machine-learning-ready row of "here's what was happening during the last 50ms" at 20Hz, carrying over values from the previou timestamp when replacements are not given.

Where data is unavailable or unreliable, it writes a consistent -999, which can never be a real sensor value. It also logs the times at which each {pebble acceleration, phone motion, location, heading} set of values was updated, so you can undo the aforementioned carrying over of values if you really want.

Hat tip to [pebble-accel-analyzer](https://github.com/kramimus/pebble-accel-analyzer), [sensorsaver](https://github.com/benvium/sensorsaver) and [pebble-accelerometer-ios-app](https://github.com/ralphiee22/pebble-accelerometer-ios-app) for being helpful examples.


*This is part of a (currently unpublished) research project, so please check back for the citation before using it in your own published work.* Also, please fork it if using it for your own research so I can see who's using it and not get scooped. :)
