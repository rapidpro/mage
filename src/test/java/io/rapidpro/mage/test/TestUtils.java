package io.rapidpro.mage.test;

import io.rapidpro.mage.api.MessageEvent;
import com.sun.jersey.api.client.ClientResponse;
import org.junit.Assert;
import org.junit.Ignore;

import java.text.DateFormat;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.GregorianCalendar;
import java.util.function.BooleanSupplier;

import static org.hamcrest.Matchers.is;
import static org.hamcrest.Matchers.notNullValue;
import static org.junit.Assert.assertThat;

/**
 * Utility methods for unit tests
 */
@Ignore
public class TestUtils {

    private final static DateFormat datasetDateFormat = new SimpleDateFormat("yyyy-MM-dd hh:mm:ss.SSS");

    /**
     * Convenience method to create a new date
     * @param year the year
     * @param month the month
     * @param day the day
     * @return the date
     * @throws IllegalArgumentException if date values are not valid
     */
    public static Date date(int year, int month, int day) {
        return date(year, month, day, 0, 0, 0);
    }

    /**
     * Convenience method to create a new date with time
     * @param year the year
     * @param month the month
     * @param day the day
     * @param hour the hour
     * @param minute the minute
     * @param second the second
     * @return the date
     * @throws IllegalArgumentException if date values are not valid
     */
    public static Date date(int year, int month, int day, int hour, int minute, int second) {
        Calendar cal = new GregorianCalendar(year, month - 1, day, hour, minute, second);
        cal.setLenient(false);
        return cal.getTime();
    }

    /**
     * Creates a date instance from string (using same format as DbUnit dataset files)
     * @param val the date string
     * @return the date
     */
    public static Date date(String val) {
        try {
            return datasetDateFormat.parse(val);
        } catch (ParseException e) {
            throw new RuntimeException(e);
        }
    }

    /**
     * Asserts a client response matches the given criteria
     * @param response the response
     * @param status the expected status code
     * @param result the expected event result
     * @return the messageId (may be null)
     */
    public static Integer assertResponse(ClientResponse response, int status, MessageEvent.Result result) {
        assertThat(response.getStatusInfo().getStatusCode(), is(status));

        MessageEvent event = response.getEntity(MessageEvent.class);
        assertThat(event.getResult(), is(result));

        // if error, check description is non-null
        if (result.equals(MessageEvent.Result.ERROR)) {
            assertThat(event.getDescription(), notNullValue());
        }
        // if not error, check message id is non-null
        else {
            assertThat(event.getMessageId(), notNullValue());
        }

        return event.getMessageId();
    }

    public static void assertBecomesTrue(BooleanSupplier condition, long timeout) throws InterruptedException {
        long started = System.currentTimeMillis();
        while (!condition.getAsBoolean()) {
            long duration = System.currentTimeMillis() - started;
            if (duration > timeout) {
                Assert.fail(String.format("Condition failed to become true after %d milliseconds", timeout));
            }

            Thread.sleep(10);
        }
    }
}