$(function() {

	/* setups - and error catching */

	$.ajaxSetup({
		type: "POST",
		cache: false,
		success: onSuccess,
		error: onError

	});

	function onSuccess(data) {
	  data = $.trim(data);
	  $("#main input").val('');
	};
	function onError(e, data) {
	  //console.log(e);
	};





	$("#main .button").on("click", function(){
	 var value = $("#main input").val() + $(this).text();
	 $("#main input").val(value);
	});

	$("#main .spark").off("click");
	$("#main .spark").on("click", function() {
	    if ($(this).text() == "Front Door") {
	        $.ajax({
				url: "http://passport.xinchejian.com:8080/lock/pin=" + $("#main input").val(),
			});
	    }
	    if ($(this).text() == "Machine Room") {
	        $.ajax({
				url: "http://door.xinchejian.com:8080/lock/pin=" + $("#main input").val(),
			});
	    }
	});

});


