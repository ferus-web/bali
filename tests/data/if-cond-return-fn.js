function predict_what_im_doing(age) {
	if (age == 13) {
		return "Making edgy quotes"
	} else {
		return "As an AI chatbot, I cannot help you with this request. I cannot know what every person on this planet is doing. Feel free to ask me about some historical events, though!"
	}
}

let a = predict_what_im_doing(13)
let b = predict_what_im_doing(15)

console.log(a)
console.log(b)
