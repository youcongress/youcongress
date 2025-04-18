// Constants
const INITIAL_GDP_IN_TRILLIONS = 110;
const INITIAL_GDP = INITIAL_GDP_IN_TRILLIONS * 1e12;
const INITIAL_POPULATION_IN_BILLIONS = 8;
const INITIAL_POPULATION = INITIAL_POPULATION_IN_BILLIONS * 1e9;
const FINAL_POPULATION_IN_BILLIONS = 10;
const FINAL_POPULATION = FINAL_POPULATION_IN_BILLIONS * 1e9;
const FINAL_YEAR = 2100;
const CURRENT_YEAR = 2024;

// DOM Elements
const donatingPopulation = document.getElementById('donatingPopulation');
const donatingPopulationValue = document.getElementById('donatingPopulationValue');
const donationPercentage = document.getElementById('donationPercentage');
const donationPercentageValue = document.getElementById('donationPercentageValue');
const donationValue = document.getElementById('donationValue');
const yearsToAGI = document.getElementById('yearsToAGI');
const yearsToAGIValue = document.getElementById('yearsToAGIValue');
const gdpGrowthPreAGI = document.getElementById('gdpGrowthPreAGI');
const gdpGrowthPreAGIValue = document.getElementById('gdpGrowthPreAGIValue');
const gdpGrowthPostAGI = document.getElementById('gdpGrowthPostAGI');
const gdpGrowthPostAGIValue = document.getElementById('gdpGrowthPostAGIValue');
const inflationRate = document.getElementById('inflationRate');
const inflationRateValue = document.getElementById('inflationRateValue');
const currentInvestment = document.getElementById('currentInvestment');
const currentInvestmentValue = document.getElementById('currentInvestmentValue');
const monthlyAddition = document.getElementById('monthlyAddition');
const monthlyAdditionValue = document.getElementById('monthlyAdditionValue');
const monthlyWithdrawal = document.getElementById('monthlyWithdrawal');
const monthlyWithdrawalValue = document.getElementById('monthlyWithdrawalValue');
const profitabilityPreAGI = document.getElementById('profitabilityPreAGI');
const profitabilityPreAGIValue = document.getElementById('profitabilityPreAGIValue');
const profitabilityPostAGI = document.getElementById('profitabilityPostAGI');
const profitabilityPostAGIValue = document.getElementById('profitabilityPostAGIValue');
const isDonating = document.getElementById('isDonating');
const resultsDiv = document.getElementById('results');
let ubiChart = null;

// Main calculation function
function calculate() {
    const donationPercent = parseFloat(donationPercentage.value);
    const donatingPopulationPercent = parseFloat(donatingPopulation.value);
    const yearsUntilAGI = parseInt(yearsToAGI.value);
    const preAGIGrowth = parseFloat(gdpGrowthPreAGI.value);
    const postAGIGrowth = parseFloat(gdpGrowthPostAGI.value);
    const inflation = parseFloat(inflationRate.value);
    const initialInvestment = parseFloat(currentInvestment.value);
    const monthlyAdditionAmount = parseFloat(monthlyAddition.value);
    const monthlyWithdrawalAmount = parseFloat(monthlyWithdrawal.value);
    const isDonatingChecked = isDonating.checked;

    let currentGDP = INITIAL_GDP;
    const years = [];
    const ubiAmounts = [];
    const ubiAmountsAdjusted = [];
    const personalWealth = [];

    for (let year = CURRENT_YEAR; year <= FINAL_YEAR; year++) {
        const isPreAGI = year < CURRENT_YEAR + yearsUntilAGI;
        const growthRate = isPreAGI ? preAGIGrowth : postAGIGrowth;

        currentGDP = calculateGDP(currentGDP, growthRate);
        const ubi = calculateUBI(currentGDP, donationPercent, donatingPopulationPercent, year);
        const wealth = calculatePersonalWealth(initialInvestment, monthlyAdditionAmount, monthlyWithdrawalAmount, year, preAGIGrowth, postAGIGrowth, yearsUntilAGI, isDonatingChecked, donationPercent);

        // Calculate inflation-adjusted UBI
        const yearsFromNow = year - CURRENT_YEAR;
        const inflationFactor = Math.pow(1 + inflation/100, yearsFromNow);
        const ubiAdjusted = ubi / inflationFactor;

        years.push(year);
        ubiAmounts.push(ubi);
        ubiAmountsAdjusted.push(ubiAdjusted);
        personalWealth.push(wealth);
    }

    updateChart(years, ubiAmounts, ubiAmountsAdjusted, personalWealth);
}

// Update value displays and trigger calculation
function updateSliderValue(slider, displayElement, suffix = '%', showYear = false, isCurrency = false) {
    const value = slider.value;
    if (showYear) {
        const targetYear = CURRENT_YEAR + parseInt(value);
        displayElement.textContent = `${value} years (${targetYear})`;
    } else if (isCurrency) {
        displayElement.textContent = formatCurrency(value);
    } else {
        displayElement.textContent = `${value}${suffix}`;
    }
    calculate();
}

// Set up event listeners for all sliders
donatingPopulation.addEventListener('input', () => {
    updateSliderValue(donatingPopulation, donatingPopulationValue);
});

donationPercentage.addEventListener('input', () => {
    updateSliderValue(donationPercentage, donationPercentageValue);
});

yearsToAGI.addEventListener('input', () => {
    updateSliderValue(yearsToAGI, yearsToAGIValue, ' years', true);
});

gdpGrowthPreAGI.addEventListener('input', () => {
    updateSliderValue(gdpGrowthPreAGI, gdpGrowthPreAGIValue);
});

gdpGrowthPostAGI.addEventListener('input', () => {
    updateSliderValue(gdpGrowthPostAGI, gdpGrowthPostAGIValue);
});

inflationRate.addEventListener('input', () => {
    updateSliderValue(inflationRate, inflationRateValue);
});

currentInvestment.addEventListener('input', () => {
    updateSliderValue(currentInvestment, currentInvestmentValue, '', false, true);
});

monthlyAddition.addEventListener('input', () => {
    updateSliderValue(monthlyAddition, monthlyAdditionValue, '', false, true);
});

monthlyWithdrawal.addEventListener('input', () => {
    updateSliderValue(monthlyWithdrawal, monthlyWithdrawalValue, '', false, true);
});

profitabilityPreAGI.addEventListener('input', () => {
    updateSliderValue(profitabilityPreAGI, profitabilityPreAGIValue);
});

profitabilityPostAGI.addEventListener('input', () => {
    updateSliderValue(profitabilityPostAGI, profitabilityPostAGIValue);
});

isDonating.addEventListener('change', () => {
    calculate();
});

// Calculate personal wealth for a given year
function calculatePersonalWealth(initialInvestment, monthlyAddition, monthlyWithdrawal, year, preAGIGrowth, postAGIGrowth, yearsUntilAGI, isDonating, donationPercent) {
    const agiYear = CURRENT_YEAR + yearsUntilAGI;
    let wealth = initialInvestment;

    for (let y = CURRENT_YEAR; y < year; y++) {
        const isPreAGI = y < agiYear;
        const growthRate = isPreAGI ? preAGIGrowth : postAGIGrowth;
        const investmentReturn = isPreAGI ? parseFloat(profitabilityPreAGI.value) : parseFloat(profitabilityPostAGI.value);

        if (isPreAGI) {
            // Pre-AGI: Add monthly contributions and apply monthly growth
            let wealthAtStartOfYear = wealth;
            for (let month = 0; month < 12; month++) {
                wealth += monthlyAddition;
                wealth = wealth * Math.pow(1 + investmentReturn/100, 1/12);
            }
            // Apply donation/tax if applicable (on the increase in wealth)
            if (isDonating) {
                const wealthIncrease = wealth - wealthAtStartOfYear;
                wealth -= wealthIncrease * (donationPercent / 100);
            }
        } else {
            // Post-AGI: Apply monthly withdrawals and growth
            let wealthAtStartOfYear = wealth;
            for (let month = 0; month < 12; month++) {
                wealth -= monthlyWithdrawal;
                wealth = wealth * Math.pow(1 + investmentReturn/100, 1/12);
            }
            // Apply donation/tax if applicable (on the increase in wealth)
            if (isDonating) {
                const wealthIncrease = wealth - wealthAtStartOfYear;
                wealth -= wealthIncrease * (donationPercent / 100);
            }
        }
    }

    return wealth;
}

// Calculate population for a given year
function calculatePopulation(year) {
    const yearsFromNow = year - CURRENT_YEAR;
    const totalYears = FINAL_YEAR - CURRENT_YEAR;
    const populationGrowth = FINAL_POPULATION - INITIAL_POPULATION;
    return INITIAL_POPULATION + (populationGrowth * (yearsFromNow / totalYears));
}

// Calculate UBI for a given year
function calculateUBI(gdp, donationPercent, donatingPopulationPercent, year) {
    const totalDonations = gdp * (donationPercent / 100) * (donatingPopulationPercent / 100);
    const currentPopulation = calculatePopulation(year);
    return totalDonations / currentPopulation;
}

// Calculate GDP growth
function calculateGDP(currentGDP, growthRate) {
    return currentGDP * (1 + growthRate / 100);
}

// Format currency
function formatCurrency(amount) {
    return new Intl.NumberFormat('en-US', {
        style: 'currency',
        currency: 'USD',
        maximumFractionDigits: 0
    }).format(amount);
}

// Create or update chart
function updateChart(years, ubiAmounts, ubiAmountsAdjusted, personalWealth) {
    const ctx = document.getElementById('ubiChart').getContext('2d');
    const agiYear = CURRENT_YEAR + parseInt(yearsToAGI.value);
    const agiIndex = years.indexOf(agiYear);

    if (ubiChart) {
        ubiChart.destroy();
    }

    ubiChart = new Chart(ctx, {
        type: 'line',
        data: {
            labels: years,
            datasets: [
                {
                    label: 'Nominal UBI',
                    data: ubiAmounts,
                    borderColor: 'rgb(59, 130, 246)',
                    backgroundColor: 'rgba(59, 130, 246, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointBackgroundColor: function(context) {
                        return context.dataIndex === agiIndex ? 'rgb(239, 68, 68)' : 'rgba(59, 130, 246, 0.1)';
                    },
                    pointRadius: function(context) {
                        return context.dataIndex === agiIndex ? 6 : 0;
                    },
                    pointHoverRadius: function(context) {
                        return context.dataIndex === agiIndex ? 8 : 0;
                    }
                },
                {
                    label: 'Inflation-adjusted UBI (2024 dollars)',
                    data: ubiAmountsAdjusted,
                    borderColor: 'rgb(16, 185, 129)',
                    backgroundColor: 'rgba(16, 185, 129, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointBackgroundColor: function(context) {
                        return context.dataIndex === agiIndex ? 'rgb(239, 68, 68)' : 'rgba(16, 185, 129, 0.1)';
                    },
                    pointRadius: function(context) {
                        return context.dataIndex === agiIndex ? 6 : 0;
                    },
                    pointHoverRadius: function(context) {
                        return context.dataIndex === agiIndex ? 8 : 0;
                    }
                },
                {
                    label: 'Personal Wealth (2024 dollars)',
                    data: personalWealth,
                    borderColor: 'rgb(168, 85, 247)',
                    backgroundColor: 'rgba(168, 85, 247, 0.1)',
                    fill: true,
                    tension: 0.4,
                    pointBackgroundColor: function(context) {
                        return context.dataIndex === agiIndex ? 'rgb(239, 68, 68)' : 'rgba(168, 85, 247, 0.1)';
                    },
                    pointRadius: function(context) {
                        return context.dataIndex === agiIndex ? 6 : 0;
                    },
                    pointHoverRadius: function(context) {
                        return context.dataIndex === agiIndex ? 8 : 0;
                    }
                }
            ]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            interaction: {
                mode: 'index',
                intersect: false
            },
            scales: {
                y: {
                    type: 'logarithmic',
                    beginAtZero: false,
                    ticks: {
                        callback: function(value) {
                            return formatCurrency(value);
                        }
                    }
                }
            },
            plugins: {
                tooltip: {
                    enabled: true,
                    mode: 'index',
                    intersect: false,
                    position: 'nearest',
                    xAlign: 'center',
                    yAlign: 'bottom',
                    padding: 10,
                    backgroundColor: 'rgba(0, 0, 0, 0.8)',
                    titleColor: 'white',
                    bodyColor: 'white',
                    callbacks: {
                        title: function(context) {
                            return `Year: ${context[0].label}`;
                        },
                        label: function(context) {
                            const value = formatCurrency(context.raw);
                            const isAGI = context.dataIndex === agiIndex;
                            const suffix = isAGI ? ' (AGI reached)' : '';
                            return `${context.dataset.label}: ${value}${suffix}`;
                        },
                        afterBody: function(context) {
                            const year = parseInt(context[0].label);
                            const yearsFromNow = year - CURRENT_YEAR;
                            const inflation = parseFloat(inflationRate.value);
                            const inflationFactor = Math.pow(1 + inflation/100, yearsFromNow);
                            return `Inflation factor: ${inflationFactor.toFixed(2)}x`;
                        }
                    }
                }
            }
        }
    });
}

// Initial calculation
calculate();
