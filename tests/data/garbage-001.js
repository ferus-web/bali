// expensive_if_else.js
let x = Math.random()
console.log("x:", x)

/* if (condition > 0) {
    console.log("Condition is true: Executing 2 expensive loops");

    let counter1 = 0;
    while (counter1 < 1_000_000) {
        counter1++;
    }
    console.log("First loop completed with counter1:", counter1);

    let counter2 = 0;
    while (counter2 < 2_000_000) {
        counter2++;
    }
    console.log("Second loop completed with counter2:", counter2);
} else {
    console.log("Condition is false: Executing 3 expensive loops");

    let counter3 = 0;
    while (counter3 < 500_000) {
        counter3++;
    }
    console.log("First loop completed with counter3:", counter3);

    let counter4 = 0;
    while (counter4 < 1_500_000) {
        counter4++;
    }
    console.log("Second loop completed with counter4:", counter4);

    let counter5 = 0;
    while (counter5 < 1_000_000) {
        counter5++;
    }
    console.log("Third loop completed with counter5:", counter5);
} */
