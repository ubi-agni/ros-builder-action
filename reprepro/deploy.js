'use strict'
const core = require('@actions/core');
const EventSource = require('eventsource');

const url = core.getInput('url');

const evtSource = new EventSource(url);

evtSource.onmessage = (event) => {
	if (event.data === '')
		evtSource.close();
	else
		console.log(event.data)
};

evtSource.onerror = (error) => {
	core.warning(error.message);
	evtSource.close();
	process.exit(1);
}
