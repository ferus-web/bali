function waste_resources(x) {
    let sin = Math.sin(x)
    console.log(sin)
    waste_resources(x + 1)
}

waste_resources(0)
