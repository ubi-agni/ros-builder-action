#!/usr/bin/env -S node

'use strict'
const core = require('@actions/core');
const EventSource = require('eventsource');

const FAILURE_MSG = 'Failed with return code ';
const url = core.getInput('url');

const evtSource = new EventSource(url);

evtSource.onmessage = (event) => {
	if (event.data === '')
		evtSource.close();
	else if (event.data.startsWith(FAILURE_MSG)) {
		core.warning(event.data);
		evtSource.close();
		const err = event.data.split(FAILURE_MSG)[1];
		process.exit(err);
	} else
		console.log(event.data)
};

evtSource.onerror = (error) => {
	core.warning(error.message);
	evtSource.close();
	process.exit(1);
}
