/*
Script Author: www.saptarang.org
Description: Navigation Drop Down Menu using jquery and css.
Date: 20 August 2011.
*/

$(document).ready(function() {
// Submenu Menu 

	$('#menu-wrapper ul li').hover(
		
		function() {
		
			$(this).find('ul:first').slideDown('slow');
				
		}, function() {
		
			$(this).find('ul').slideUp('fast');
			
		});

});
