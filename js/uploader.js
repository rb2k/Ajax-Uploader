// This is responsible for keeping the upload percentage updated
// We'll recursively call ourselves to refresh the status on the website
var updateUploadProgress = function() {
	// check upload progess
	$.get('/progress', {'uid': UID}, function(data) {
		// if we have hit 100% we're done and can request the URL
		if(data.progress < 100) {
			if(data.progress) $('#progress').text('uploaded: ' + data.progress + '%');
			setTimeout('updateUploadProgress()',500);
			return true;
		}
		// if we arrive here, we had a progress of >= 100
		// Just in case the file was so small that we never got arround to update the progress, 
		// let's change it to 100%
		$('#progress').text('uploaded: 100%');
		displayUploadURL();
	}, 'json');
};
// This will show the user the URL for the file and post the entered description to the server
var displayUploadURL = function() {
	$.get('/filepath', {'uid': UID}, function(data) {
		$('#progress').append(' | <a href="'+data.path+'" target="_blank">uploaded to here</a>');
		// Now that we have the path, we can go on and post the description to the server
		postDescription();
	}, 'json');
};
// This is used to post the description to the server after the upload is done
// and we showed the user the file path
var postDescription = function() {
	$.post('/description', {
		'uid': UID,
		'description': $('#description').val()
	}, function(data) {
		$('#progress').append('<br />description saved');
	}, 'json');
};
